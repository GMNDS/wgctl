require "../cli/context"
require "../output/formatter"
require "../output/json_formatter"

module Wgctl
  module Commands
    class StatusCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = context.interface || args.first?
        iface = context.load_interface(target_name, hint_command: "status")

        if context.json_output
          puts Output::JsonFormatter.format_status(iface)
        else
          puts Output::Formatter.format_status(iface)
        end
      end
    end
  end
end
