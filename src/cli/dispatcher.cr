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
require "../commands/menu_command"
require "../commands/daemon_command"
require "../commands/remote_command"
require "./help"

module Wgctl
  module CLI
    class Dispatcher
      def self.run(argv : Array(String) = ARGV)
        original_argv = argv.dup
        # 1. Handle help requests before option parsing to allow rich contextual help
        if argv.first? == "help"
          cmd = argv[1]?
          subcmd = argv[2]?
          Help.print_command_help(cmd, subcmd)
          return
        end

        if argv.includes?("--help") || argv.includes?("-h")
          clean_args = argv.reject { |a| a == "--help" || a == "-h" }
          if clean_args.empty?
            Help.print_main_help
          else
            cmd = clean_args[0]
            subcmd = clean_args[1]?
            Help.print_command_help(cmd, subcmd)
          end
          return
        end

        if argv == ["-v"] || argv == ["--version"]
          Commands::VersionCommand.run
          return
        end

        context = Context.new
        positional = [] of String

        parser = OptionParser.new do |opts|
          opts.banner = Help.main_help_text

          opts.on("-c CONFIG", "--config CONFIG", "Path to WireGuard configuration file") do |cfg|
            context.config_file = cfg
          end

          opts.on("-i IFACE", "--interface IFACE", "Specify target WireGuard interface (e.g. wg0, wg1)") do |iface|
            context.interface = iface
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

          opts.on("--skip-packages", "Skip automatic installation of system packages") do
            context.skip_pkg_install = true
          end

          # Daemon and token options
          opts.on("-H HOST", "--host HOST", "Host IP to bind daemon (default: 0.0.0.0)") do |h|
            context.host = h
          end

          opts.on("--cert CERT", "Path to SSL/TLS certificate chain") do |cert|
            context.cert = cert
          end

          opts.on("--key KEY", "Path to SSL/TLS private key") do |key|
            context.key = key
          end

          opts.on("--cors ORIGIN", "Allowed CORS origin for daemon (default: *)") do |cors|
            context.cors = cors
          end

          opts.on("-e DURATION", "--expires DURATION", "Token expiration duration (e.g. 7d, 30d, 90d, 1y, never)") do |exp|
            context.expires = exp
          end

          opts.on("-f", "--foreground", "Run daemon in foreground instead of background") do
            context.foreground = true
          end

          opts.on("--daemon-foreground", "Internal flag to run daemon process in foreground") do
            context.foreground = true
          end

          opts.on("--remote URL", "Target remote wgctl daemon URL (e.g. https://vpn.example.com:7443)") do |url|
            context.remote_url = url
          end

          opts.on("-t TOKEN", "--token TOKEN", "Bearer authentication token for remote daemon") do |token|
            context.remote_token = token
          end

          opts.on("--profile NAME", "Remote profile name to use from ~/.config/wgctl/remote.json") do |prof|
            context.remote_profile_name = prof
          end

          opts.on("-v", "--version", "Show version") do
            Commands::VersionCommand.run
            exit(0)
          end

          opts.on("-h", "--help", "Show help") do
            Help.print_main_help
            exit(0)
          end

          opts.unknown_args do |args|
            positional = args
          end
        end

        parser.parse(argv)

        if positional.empty?
          if STDIN.tty?
            Commands::MenuCommand.run(context, [] of String)
          else
            Commands::StatusCommand.run(context, [] of String)
          end
          return
        end

        command = positional.shift

        case command
        when "status"
          Commands::StatusCommand.run(context, positional)
        when "menu", "tui"
          Commands::MenuCommand.run(context, positional)
        when "daemon"
          Commands::DaemonCommand.run(context, positional)
        when "remote", "attach"
          Commands::RemoteCommand.run(context, positional)
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
          cmd = positional.shift?
          subcmd = positional.shift?
          Help.print_command_help(cmd, subcmd)
        else
          raise "Unknown command: '#{command}'. Run 'wgctl --help' for usage."
        end
      rescue ex
        # If permission was denied on Unix and sudo is available in a TTY, re-exec via sudo
        {% if flag?(:unix) %}
          if (ex.is_a?(File::AccessDeniedError) || (ex.message || "").includes?("Permission denied")) &&
             LibC.getuid != 0 &&
             STDIN.tty? &&
             Process.find_executable("sudo")
            exe = Process.executable_path || "wgctl"
            status = Process.run("sudo", [exe] + original_argv, input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
            exit(status.exit_code)
          end
        {% end %}

        STDERR.puts "Error: #{ex.message}"
        exit(1)
      end
    end
  end
end
