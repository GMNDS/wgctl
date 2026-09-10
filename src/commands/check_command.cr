require "../cli/context"
require "../output/formatter"
require "../output/json_formatter"
require "../config/validator"

module Wgctl
  module Commands
    class CheckCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = args.first?
        iface = context.load_interface(target_name)

        report = Config::Validator.validate(iface)

        if context.json_output
          puts Output::JsonFormatter.format_check(report)
        else
          puts Output::Formatter.format_check(report)
        end

        unless report.valid?
          exit(1)
        end
      end
    end
  end
end
