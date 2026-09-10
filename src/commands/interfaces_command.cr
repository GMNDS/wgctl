require "../cli/context"
require "../output/formatter"
require "../output/json_formatter"
require "../wireguard/runner"
require "../config/parser"

module Wgctl
  module Commands
    class InterfacesCommand
      def self.run(context : CLI::Context, args : Array(String))
        configs = context.available_configs
        active_ifaces = WireGuard::Runner.list_active_interfaces

        all_names = (configs.keys + active_ifaces).uniq.sort
        if all_names.empty?
          if context.json_output
            puts "[]"
          else
            puts "No WireGuard interfaces found."
          end
          return
        end

        interfaces = [] of Models::Interface

        all_names.each do |name|
          path = configs[name]? || "/etc/wireguard/#{name}.conf"
          if File.exists?(path)
            iface = Config::Parser.parse_file(path, name)
          else
            iface = Models::Interface.new(name: name, config_path: path)
          end

          if active_ifaces.includes?(name)
            iface.active = true
            if dump = WireGuard::Runner.fetch_dump(name)
              WireGuard::DumpParser.parse(dump, iface)
            end
          end

          interfaces << iface
        end

        if context.json_output
          puts Output::JsonFormatter.format_interfaces(interfaces)
        else
          puts Output::Formatter.format_interfaces(interfaces)
        end
      end
    end
  end
end
