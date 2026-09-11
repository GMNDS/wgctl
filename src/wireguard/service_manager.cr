require "process"

module Wgctl
  module WireGuard
    class ServiceManager
      # Enables and starts the wireguard systemd service for an interface
      def self.enable_and_start(interface_name : String) : Tuple(Bool, String)
        service_name = "wg-quick@#{interface_name}.service"

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run("systemctl", ["enable", "--now", service_name], output: stdout, error: stderr)

        if status.success?
          {true, "Enabled and started #{service_name}"}
        else
          err = stderr.to_s.strip
          {false, "Failed to start #{service_name}: #{err}"}
        end
      rescue ex
        {false, "systemctl command error: #{ex.message}"}
      end

      # Checks if the service is currently running
      def self.active?(interface_name : String) : Bool
        service_name = "wg-quick@#{interface_name}.service"
        Process.run("systemctl", ["is-active", "--quiet", service_name]).success?
      rescue
        false
      end
    end
  end
end
