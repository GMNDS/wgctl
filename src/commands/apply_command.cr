require "../cli/context"
require "../wireguard/runner"

module Wgctl
  module Commands
    class ApplyCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = context.interface || args.first?

        if context.remote?
          client = context.remote_client
          iface_name = target_name || context.interface || client.list_interfaces.first? || "wg0"
          msg = client.apply_interface(iface_name)
          puts "✓ #{msg}"
          return
        end

        iface = context.load_interface(target_name, hint_command: "apply")

        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Configuration file not found for interface #{iface.name}."
        end

        success, msg = WireGuard::Runner.apply_syncconf(iface.name, config_path)
        if success
          puts "✓ #{msg}"
        else
          STDERR.puts "ERROR: #{msg}"
          exit(1)
        end
      end
    end
  end
end
