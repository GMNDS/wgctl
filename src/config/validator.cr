require "json"
require "../models/interface"

module Wgctl
  module Config
    enum Severity
      Info
      Warning
      Error
    end

    struct Issue
      include JSON::Serializable

      property severity : Severity
      property message : String

      def initialize(@severity : Severity, @message : String)
      end
    end

    class ValidationReport
      include JSON::Serializable

      property interface_name : String
      property peer_count : Int32
      property issues : Array(Issue) = [] of Issue

      def initialize(@interface_name : String, @peer_count : Int32)
      end

      def add_info(msg : String)
        @issues << Issue.new(Severity::Info, msg)
      end

      def add_warn(msg : String)
        @issues << Issue.new(Severity::Warning, msg)
      end

      def add_error(msg : String)
        @issues << Issue.new(Severity::Error, msg)
      end

      def valid? : Bool
        @issues.none? { |i| i.severity == Severity::Error }
      end

      def error_count : Int32
        @issues.count { |i| i.severity == Severity::Error }
      end

      def warning_count : Int32
        @issues.count { |i| i.severity == Severity::Warning }
      end
    end

    class Validator
      def self.validate(iface : Models::Interface) : ValidationReport
        report = ValidationReport.new(iface.name, iface.peers.size)

        # 1. Interface checks
        unless iface.name =~ /^[a-zA-Z0-9_\-\.]{1,32}$/
          report.add_error("invalid interface name '#{iface.name}': must be 1-32 characters and contain only alphanumeric, hyphens, underscores, or dots")
        end

        if iface.address.empty?
          report.add_warn("interface #{iface.name} has no Address configured")
        end

        if iface.listen_port.nil?
          report.add_info("interface #{iface.name} has no ListenPort configured (wg-quick will use default or dynamic port)")
        end

        if iface.private_key.nil? || iface.private_key.to_s.empty?
          report.add_warn("interface #{iface.name} has no PrivateKey configured")
        end

        # 2. Tracking collections for duplicate detection
        seen_names = Hash(String, Array(String)).new # name -> list of public keys
        seen_keys = Hash(String, Array(String)).new  # public_key -> list of peer names
        seen_ips = Hash(String, Array(String)).new   # ip/cidr -> list of peer identifiers

        # Add interface IPs to seen_ips
        iface.address.each do |addr|
          clean = addr.strip
          seen_ips[clean] ||= [] of String
          seen_ips[clean] << "interface #{iface.name}"
        end

        # 3. Peer checks
        iface.peers.each_with_index do |peer, idx|
          peer_id = peer.has_name? ? peer.name : peer.short_key

          # Check Public Key
          if peer.public_key.strip.empty?
            report.add_error("peer ##{idx + 1} has no PublicKey")
          else
            seen_keys[peer.public_key] ||= [] of String
            seen_keys[peer.public_key] << peer_id
          end

          # Check Name
          if !peer.has_name?
            report.add_warn("peer #{peer.short_key} has no wgctl:name")
          else
            name = peer.name.not_nil!
            # Check valid characters and reject newlines for name
            if name.includes?("\n") || name.includes?("\r")
              report.add_error("peer name contains invalid newline characters")
            elsif !(name =~ /^[a-zA-Z0-9_\-\.]{1,64}$/)
              report.add_error("peer name '#{name}' contains invalid characters; must be 1-64 alphanumeric, hyphens, underscores, or dots")
            end
            seen_names[name.downcase] ||= [] of String
            seen_names[name.downcase] << peer.short_key
          end

          # Check Description and Device for CRLF/newline injection
          if desc = peer.description
            if desc.includes?("\n") || desc.includes?("\r")
              report.add_error("peer #{peer_id} description contains invalid newline characters")
            elsif desc.size > 255
              report.add_error("peer #{peer_id} description exceeds maximum length of 255 characters")
            end
          end

          if dev = peer.device
            if dev.includes?("\n") || dev.includes?("\r")
              report.add_error("peer #{peer_id} device contains invalid newline characters")
            elsif dev.size > 64
              report.add_error("peer #{peer_id} device exceeds maximum length of 64 characters")
            end
          end

          peer.metadata.extra.each do |k, v|
            if !(k =~ /^[a-zA-Z0-9_\-]{1,64}$/)
              report.add_error("peer #{peer_id} extra metadata key '#{k}' contains invalid characters")
            end
            if v.includes?("\n") || v.includes?("\r")
              report.add_error("peer #{peer_id} extra metadata value for '#{k}' contains invalid newline characters")
            end
          end

          # Check Allowed IPs
          if peer.allowed_ips.empty?
            report.add_warn("peer #{peer_id} has no AllowedIPs")
          else
            peer.allowed_ips.each do |ip_cidr|
              clean_ip = ip_cidr.strip
              seen_ips[clean_ip] ||= [] of String
              seen_ips[clean_ip] << peer_id
            end
          end
        end

        # Check duplicate names
        seen_names.each do |name, peers_list|
          if peers_list.size > 1
            report.add_error("duplicate peer name '#{name}' used by multiple peers: #{peers_list.join(", ")}")
          end
        end

        # Check duplicate public keys
        seen_keys.each do |key, peers_list|
          if peers_list.size > 1
            report.add_error("duplicate public key #{key[0...8]}... used by: #{peers_list.join(", ")}")
          end
        end

        # Check duplicate IPs
        has_duplicate_ips = false
        seen_ips.each do |ip, owners|
          if owners.size > 1
            has_duplicate_ips = true
            report.add_error("#{ip} is assigned to multiple peers: #{owners.join(", ")}")
          end
        end

        report
      end
    end
  end
end
