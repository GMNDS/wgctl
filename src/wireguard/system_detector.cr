require "process"

module Wgctl
  module WireGuard
    class SystemDetector
      # Detects the default network interface used for internet routing (e.g. eth0, ens3)
      def self.detect_default_wan_interface : String
        stdout = IO::Memory.new
        status = Process.run("ip", ["route", "get", "1.1.1.1"], output: stdout)
        if status.success?
          output = stdout.to_s
          if output =~ /dev\s+([a-zA-Z0-9_\-\.]+)/
            return $1.strip
          end
        end

        # Fallback: check 'ip route show default'
        stdout.clear
        status = Process.run("ip", ["route", "show", "default"], output: stdout)
        if status.success?
          output = stdout.to_s
          if output =~ /dev\s+([a-zA-Z0-9_\-\.]+)/
            return $1.strip
          end
        end

        "eth0"
      rescue
        "eth0"
      end

      # Detects public IPv4 address, querying fast resolvers if behind NAT
      def self.detect_public_ip : String
        # 1. Check local non-private IPs first
        local_ips = list_local_ipv4s
        public_local = local_ips.find { |ip| !private_ip?(ip) }
        return public_local if public_local

        # 2. Behind NAT: Query fast external endpoints
        endpoints = [
          "https://api.ipify.org",
          "https://ifconfig.me/ip",
          "http://ip1.dynupdate.no-ip.com/"
        ]

        endpoints.each do |url|
          stdout = IO::Memory.new
          status = Process.run("curl", ["-fsSL", "-m", "3", "-4", url], output: stdout)
          if status.success?
            ip = stdout.to_s.strip
            return ip if ip =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/
          end
        rescue
        end

        local_ips.first? || "127.0.0.1"
      rescue
        "127.0.0.1"
      end

      # Lists all local IPv4 addresses excluding loopback
      def self.list_local_ipv4s : Array(String)
        stdout = IO::Memory.new
        status = Process.run("ip", ["-4", "addr", "show"], output: stdout)
        return [] of String unless status.success?

        ips = [] of String
        stdout.to_s.lines.each do |line|
          if line =~ /inet\s+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\/\d+/
            ip = $1
            ips << ip unless ip.starts_with?("127.")
          end
        end
        ips
      rescue
        [] of String
      end

      # Determines if an IPv4 address is in RFC 1918 private ranges
      def self.private_ip?(ip : String) : Bool
        return true if ip.starts_with?("10.")
        return true if ip.starts_with?("192.168.")
        return true if ip.starts_with?("127.")
        if ip =~ /^172\.(\d+)\./
          second_octet = $1.to_i? || 0
          return true if second_octet >= 16 && second_octet <= 31
        end
        false
      end

      # Detects public IPv6 if available
      def self.detect_public_ipv6 : String?
        stdout = IO::Memory.new
        status = Process.run("ip", ["-6", "addr", "show"], output: stdout)
        return nil unless status.success?

        stdout.to_s.lines.each do |line|
          # Public IPv6 addresses usually start with 2 or 3
          if line =~ /inet6\s+([23][0-9a-fA-F:]+)\/\d+/
            return $1
          end
        end
        nil
      rescue
        nil
      end
    end
  end
end
