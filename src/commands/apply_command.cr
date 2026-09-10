require "../cli/context"
require "../wireguard/runner"

module Wgctl
  module Commands
    class ApplyCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = args.first?
        iface = context.load_interface(target_name)

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
