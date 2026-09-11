require "process"

module Wgctl
  module WireGuard
    class SysctlManager
      SYSCTL_FILE = "/etc/sysctl.d/99-wireguard-forward.conf"

      # Configures net.ipv4.ip_forward=1 and IPv6 forwarding
      def self.enable_forwarding(enable_ipv6 : Bool = false) : Tuple(Bool, String)
        content = IO::Memory.new
        content.puts "net.ipv4.ip_forward=1"
        if enable_ipv6
          content.puts "net.ipv6.conf.all.forwarding=1"
        end

        # Try writing sysctl.d file
        begin
          Dir.mkdir_p("/etc/sysctl.d") unless Dir.exists?("/etc/sysctl.d")
          File.write(SYSCTL_FILE, content.to_s)
        rescue ex
          # If not root or read-only filesystem, return false
          return {false, "Could not write to #{SYSCTL_FILE}: #{ex.message}"}
        end

        # Apply live
        Process.run("sysctl", ["-p", SYSCTL_FILE]) rescue nil

        # Also write directly to /proc if available
        if File.exists?("/proc/sys/net/ipv4/ip_forward")
          File.write("/proc/sys/net/ipv4/ip_forward", "1\n") rescue nil
        end

        if enable_ipv6 && File.exists?("/proc/sys/net/ipv6/conf/all/forwarding")
          File.write("/proc/sys/net/ipv6/conf/all/forwarding", "1\n") rescue nil
        end

        {true, "Enabled IP forwarding in #{SYSCTL_FILE}"}
      end
    end
  end
end
