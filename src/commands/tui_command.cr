require "../cli/context"
require "../tui/app"

module Wgctl
  module Commands
    class TUICommand
      def self.run(context : CLI::Context, args : Array(String))
        unless STDIN.tty?
          raise "TUI requires an interactive terminal (TTY)."
        end

        target_name = args.first?
        iface = context.load_interface(target_name)

        app = TUI::App.new(context, iface)
        app.run
      end
    end
  end
end
