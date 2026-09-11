require "../cli/context"
require "../output/formatter"
require "../output/json_formatter"

module Wgctl
  module Commands
    class PeersCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = context.interface || args.first?
        iface = context.load_interface(target_name, hint_command: "peers")

        if context.json_output
          puts Output::JsonFormatter.format_peers(iface)
        else
          puts Output::Formatter.format_peers(iface)
        end
      end
    end
  end
end
