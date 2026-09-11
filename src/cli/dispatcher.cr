require "option_parser"
require "./context"
require "../commands/status_command"
require "../commands/interfaces_command"
require "../commands/peers_command"
require "../commands/peer_show_command"
require "../commands/peer_add_command"
require "../commands/peer_edit_command"
require "../commands/peer_remove_command"
require "../commands/client_command"
require "../commands/check_command"
require "../commands/apply_command"
require "../commands/version_command"
require "../commands/init_command"
require "../commands/migrate_command"
require "../commands/tui_command"

module Wgctl
  module CLI
    class Dispatcher
      def self.run(argv : Array(String) = ARGV)
        context = Context.new
        positional = [] of String

        parser = OptionParser.new do |opts|
          opts.banner = <<-BANNER
          wgctl - Friendly WireGuard management CLI

          Usage:
            wgctl <command> [arguments...] [options...]

          Commands:
            status [interface]             Show friendly status and active peers
            tui [interface]                Launch interactive Terminal UI dashboard
            init [interface]               Initialize a new WireGuard server interface
            migrate [interface]            Migrate legacy comments (# BEGIN_PEER) to # wgctl:*
            interfaces                     List all discovered WireGuard interfaces
            peers [interface]              List all peers in an interface
            peer show <name|key>           Show details for a single peer
            peer <name|key>                Shortcut for 'peer show'
            peer add <name> --ip <ip|auto> Add a new peer and generate client keys
            peer edit <name|key>           Edit peer metadata, IP, or properties
            peer remove <name|key>         Safely remove a peer
            client <name|key>              Generate WireGuard client configuration
            check [interface]              Validate configuration integrity and detect conflicts
            apply [interface]              Sync interface configuration live without downtime
            version                        Show version information

          Global Options:
          BANNER

          opts.on("-c CONFIG", "--config CONFIG", "Path to WireGuard configuration file") do |cfg|
            context.config_file = cfg
          end

          opts.on("--json", "Output results in JSON format") do
            context.json_output = true
          end

          opts.on("--dry-run", "Simulate changes without modifying files or interface") do
            context.dry_run = true
          end

          opts.on("--ip IP", "IP address for peer (e.g. 10.13.14.9 or 'auto')") do |ip|
            context.ip = ip
          end

          opts.on("--description DESC", "Description for peer") do |desc|
            context.description = desc
          end

          opts.on("--device DEVICE", "Device type for peer (e.g. mobile, server, laptop)") do |dev|
            context.device = dev
          end

          opts.on("--name NAME", "New name for peer when editing") do |n|
            context.name = n
          end

          opts.on("--keepalive SECONDS", "Persistent keepalive interval in seconds") do |sec|
            context.keepalive = sec.to_i?
          end

          opts.on("--preshared-key", "Generate and require a pre-shared key") do
            context.preshared_key = "generate"
          end

          opts.on("--endpoint ENDPOINT", "Server public endpoint (host:port) for client config") do |ep|
            context.endpoint = ep
          end

          opts.on("-o FILE", "--output FILE", "Save generated client configuration to a file (mode 0600)") do |file|
            context.output_file = file
          end

          opts.on("--qr", "Render client configuration as a terminal QR code") do
            context.qr_code = true
          end

          opts.on("--no-apply", "Do not apply changes to active interface") do
            context.no_apply = true
          end

          # Server init options
          opts.on("--wan IFACE", "Default external WAN interface for NAT rules (e.g. eth0)") do |wan|
            context.wan_interface = wan
          end

          opts.on("--public-ip IP", "Public IP or hostname of the server") do |pub|
            context.public_ip = pub
          end

          opts.on("--port PORT", "Listen port for WireGuard server") do |p|
            context.port = p.to_i?
          end

          opts.on("--subnet CIDR", "Internal VPN subnet (e.g. 10.13.14.1/24)") do |sub|
            context.subnet = sub
          end

          opts.on("--dns DNS", "DNS resolvers for VPN clients (e.g. 1.1.1.1, 1.0.0.1)") do |d|
            context.dns = d
          end

          opts.on("--first-client NAME", "Name of initial client to generate on init") do |fc|
            context.first_client = fc
          end

          opts.on("-y", "--non-interactive", "Run without interactive wizard prompts") do
            context.non_interactive = true
          end

          opts.on("--no-firewall", "Do not add PostUp/PostDown NAT firewall rules") do
            context.no_firewall = true
          end

          opts.on("--no-start", "Do not start/enable systemd service automatically") do
            context.no_start = true
          end

          opts.on("-v", "--version", "Show version") do
            Commands::VersionCommand.run
            exit(0)
          end

          opts.on("-h", "--help", "Show help") do
            puts opts
            exit(0)
          end

          opts.unknown_args do |args|
            positional = args
          end
        end

        parser.parse(argv)

        if positional.empty?
          # Default to status if no command given
          Commands::StatusCommand.run(context, [] of String)
          return
        end

        command = positional.shift

        case command
        when "status"
          Commands::StatusCommand.run(context, positional)
        when "tui"
          Commands::TUICommand.run(context, positional)
        when "init"
          Commands::InitCommand.run(context, positional)
        when "migrate"
          Commands::MigrateCommand.run(context, positional)
        when "interfaces"
          Commands::InterfacesCommand.run(context, positional)
        when "peers"
          Commands::PeersCommand.run(context, positional)
        when "peer"
          subcommand = positional.shift?
          if subcommand.nil?
            raise "Missing subcommand or peer name. Usage: wgctl peer <show|add|edit|remove> or wgctl peer <name>"
          end

          case subcommand
          when "show"
            Commands::PeerShowCommand.run(context, positional)
          when "add"
            Commands::PeerAddCommand.run(context, positional)
          when "edit"
            Commands::PeerEditCommand.run(context, positional)
          when "remove"
            Commands::PeerRemoveCommand.run(context, positional)
          else
            # Shortcut: `wgctl peer asteri-c` -> `wgctl peer show asteri-c`
            Commands::PeerShowCommand.run(context, [subcommand] + positional)
          end
        when "client"
          Commands::ClientCommand.run(context, positional)
        when "check"
          Commands::CheckCommand.run(context, positional)
        when "apply"
          Commands::ApplyCommand.run(context, positional)
        when "version"
          Commands::VersionCommand.run
        when "help"
          puts parser
        else
          raise "Unknown command: '#{command}'. Run 'wgctl --help' for usage."
        end
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        exit(1)
      end
    end
  end
end
