module Wgctl
  module CLI
    module Help
      def self.main_help_text : String
        <<-HELP
wgctl - Friendly WireGuard management CLI

USAGE:
  wgctl [command] [arguments...] [options...]
  wgctl                          (Interactive menu if run in terminal)

COMMANDS BY CATEGORY:

  Interactive & Monitoring:
    status [interface]             Real-time interface dashboard and peer activity
    menu [interface]               Interactive terminal assistant with guided prompts (alias: tui)
    interfaces                     List all discovered WireGuard interfaces

  Peer Management:
    peer add <name> [options]      Register new peer, auto-allocate IP, and generate client keys
    peer show <name|key>           Inspect detailed peer configuration, traffic, and handshake
    peer edit <name|key> [options] Update peer metadata (name, description, device) or IP
    peer remove <name|key>         Safely delete peer, create backup, and sync kernel live
    peers [interface]              List all peers in an interface with friendly names and IPs

  Client Export:
    client <name|key> [options]    Export WireGuard client .conf or display mobile QR code

  Server Administration:
    init [interface] [options]     Setup and configure complete WireGuard server (wizard or -y)
    apply [interface]              Sync interface configuration to kernel live without downtime
    check [interface]              Validate configuration syntax, IP conflicts, and keys
    migrate [interface]            Convert legacy comments (# BEGIN_PEER) to # wgctl:* metadata

  Headless & REST API:
    daemon start [options]         Run HTTP/WebSocket REST daemon for remote web/app/TUI clients
    daemon token <action>          Manage bearer authentication tokens (create, list, revoke)

  General:
    version                        Show version information
    help [command]                 Show detailed help and examples for a specific command

COMMON EXAMPLES:
  # 1. Quick interactive assistant
  wgctl

  # 2. View live status of wg0
  wgctl status wg0

  # 3. Add a peer with automatic IP allocation and client keys
  wgctl peer add phone --ip auto --device mobile

  # 4. Display mobile QR code in terminal for official WireGuard app
  wgctl client phone --qr

  # 5. Export peer configuration to a secure file (mode 0600)
  wgctl client laptop -o ./laptop.conf

  # 6. Safely remove a peer and sync kernel live
  wgctl peer remove phone

  # 7. Step-by-step WireGuard server initialization wizard
  wgctl init wg0

  # 8. Run REST API daemon on port 7443 with TLS
  wgctl daemon start --port 7443 --cert cert.pem --key key.pem

Run 'wgctl help <command>' or 'wgctl <command> --help' for command-specific options.
HELP
      end

      def self.print_main_help
        puts main_help_text
      end

      def self.print_peer_help(subcommand : String? = nil)
        case subcommand
        when "add"
          puts <<-HELP
wgctl peer add - Register a new peer with automatic or explicit IP

USAGE:
  wgctl peer add <name> [interface] [options]

ARGUMENTS:
  <name>                          Unique friendly name for the peer (e.g. phone, alice-laptop)
  [interface]                     WireGuard interface (optional if -i is used or only one interface exists)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --ip <IP|auto>                  Assign specific IP (e.g. 10.13.14.9/32) or use 'auto' for next free IP
  --description <text>            Friendly description or notes (e.g. "Alice work laptop")
  --device <type>                 Device type (e.g. mobile, laptop, desktop, server)
  --keepalive <seconds>           PersistentKeepalive interval in seconds (default: 25)
  --preshared-key                 Generate and require a Curve25519 Pre-shared Key (PSK)
  --no-apply                      Write to .conf file without applying changes to active interface
  --dry-run                       Simulate peer addition without modifying files or kernel
  -c, --config <file>             Explicit path to WireGuard configuration file

EXAMPLES:
  # Add peer with automatic next free IP
  wgctl peer add phone --ip auto --device mobile

  # Specify interface via flag or positional
  wgctl peer add phone -i wg0 --ip auto
  wgctl peer add phone wg0 --ip auto

  # Add peer with specific IP and description
  wgctl peer add office-nas --ip 10.13.14.50/32 --description "Storage Server" --device server

  # Add peer with pre-shared key
  wgctl peer add boss-ipad --ip auto --preshared-key
HELP

        when "edit"
          puts <<-HELP
wgctl peer edit - Edit metadata, IP, or properties of an existing peer

USAGE:
  wgctl peer edit <name|key> [interface] [options]

ARGUMENTS:
  <name|key>                      Peer name or base64 public key
  [interface]                     WireGuard interface (optional if -i is used or only one interface exists)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --name <new-name>               Rename the peer
  --description <text>            Update description
  --device <type>                 Update device type (mobile, laptop, desktop, server)
  --ip <IP>                       Change peer IP address (e.g. 10.13.14.20/32)
  --keepalive <seconds>           Update PersistentKeepalive interval
  --no-apply                      Do not apply changes to active interface
  --dry-run                       Simulate changes without modifying files or kernel
  -c, --config <file>             Explicit path to WireGuard configuration file

EXAMPLES:
  # Rename a peer and update description
  wgctl peer edit phone --name phone-new --description "iPhone 16 Pro"

  # Specify interface via flag or positional
  wgctl peer edit phone -i wg0 --description "iPhone 16 Pro"
  wgctl peer edit phone wg0 --ip 10.13.14.25/32
HELP

        when "remove"
          puts <<-HELP
wgctl peer remove - Safely remove a peer and sync kernel live

USAGE:
  wgctl peer remove <name|key> [interface] [options]

ARGUMENTS:
  <name|key>                      Peer name or base64 public key to remove
  [interface]                     WireGuard interface (optional if -i is used or only one interface exists)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --no-apply                      Do not sync interface in kernel after removing
  --dry-run                       Simulate removal without modifying files or kernel
  -c, --config <file>             Explicit path to WireGuard configuration file

NOTE:
  A timestamped backup is automatically created in the backups/ directory before removal.
  If the interface is active, 'wg syncconf' is executed to remove the peer without dropping tunnels.

EXAMPLES:
  wgctl peer remove phone
  wgctl peer remove phone -i wg0
  wgctl peer remove phone wg0
  wgctl peer remove laptop --dry-run
HELP

        when "show"
          puts <<-HELP
wgctl peer show - Display detailed information for a single peer

USAGE:
  wgctl peer show <name|key> [interface] [options]
  wgctl peer <name|key> [interface] [options]

ARGUMENTS:
  <name|key>                      Peer name or base64 public key
  [interface]                     WireGuard interface (optional if -i is used or only one interface exists)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --json                          Output peer details in JSON format
  -c, --config <file>             Explicit path to WireGuard configuration file

EXAMPLES:
  # Display peer in default/single interface
  wgctl peer show phone

  # Specify interface via flag
  wgctl peer show asteri-m -i wg0
  wgctl peer show asteri-m --interface wg1

  # Specify interface as positional argument
  wgctl peer show asteri-m wg0
  wgctl peer asteri-m wg0

  # Output in JSON format
  wgctl peer show phone -i wg0 --json
HELP

        else
          puts <<-HELP
wgctl peer - Comprehensive WireGuard peer management

USAGE:
  wgctl peer <command> [arguments...] [options...]
  wgctl peer <name|key>           (Shortcut for 'peer show')

COMMANDS:
  add <name> [options]            Add a new peer with auto/manual IP and generate client keys
  show <name|key>                 Show detailed peer information, activity, and traffic
  edit <name|key> [options]       Update peer name, description, device type, or IP
  remove <name|key> [options]     Safely remove peer, create backup, and sync kernel live
  peers [interface]               List all peers in an interface

PEER OPTIONS:
  -i, --interface <name>          Target WireGuard interface (e.g. wg0, wg1)
  --ip <IP|auto>                  IP address (e.g. 10.13.14.9 or 'auto')
  --name <new-name>               New name when editing
  --description <text>            Peer description
  --device <type>                 Device type (mobile, laptop, desktop, server)
  --keepalive <seconds>           PersistentKeepalive interval
  --preshared-key                 Generate Pre-shared Key (PSK)
  --no-apply                      Do not apply changes to active interface
  --dry-run                       Simulate changes without modifying files

EXAMPLES:
  wgctl peer add phone --ip auto --device mobile
  wgctl peer show asteri-m -i wg0
  wgctl peer edit phone --description "Alice Phone"
  wgctl peer remove phone -i wg0

Run 'wgctl help peer <add|edit|remove|show>' for detailed options on each subcommand.
HELP
        end
      end

      def self.print_client_help
        puts <<-HELP
wgctl client - Generate WireGuard client configuration or mobile QR code

USAGE:
  wgctl client <name|key> [interface] [options]

ARGUMENTS:
  <name|key>                      Peer name or base64 public key
  [interface]                     WireGuard interface (optional if -i is used or only one interface exists)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --qr                            Display client configuration as terminal QR code (ANSI UTF-8)
  -o, --output <file>             Save client configuration to file with strict mode 0600 permissions
  --endpoint <host:port>          Override server public endpoint (e.g. vpn.example.com:51820)
  -c, --config <file>             Path to WireGuard server configuration file

EXAMPLES:
  # Print client configuration to terminal
  wgctl client phone

  # Specify interface via flag or positional
  wgctl client phone -i wg0
  wgctl client phone wg0 --qr

  # Scan directly with the official WireGuard mobile app (iOS / Android)
  wgctl client phone --qr

  # Save configuration to a file for distribution
  wgctl client laptop -o ./laptop-vpn.conf

  # Override server endpoint (useful for Dynamic DNS or port-forwarding)
  wgctl client phone --endpoint vpn.mydomain.com:51820 --qr
HELP
      end

      def self.print_init_help
        puts <<-HELP
wgctl init - Initialize a new WireGuard server interface from scratch

USAGE:
  wgctl init [interface] [options]

ARGUMENTS:
  [interface]                     Name of interface to create (default: wg0)

OPTIONS:
  -i, --interface <name>          Name of interface to create (alias for [interface])
  --wan <interface>               External WAN network interface for NAT forwarding (e.g. eth0, ens3)
  --public-ip <IP|host>           Public IP address or hostname for clients to connect to
  --port <port>                   UDP listen port for WireGuard (default: 51820)
  --subnet <CIDR>                 Internal VPN subnet CIDR (default: 10.13.14.1/24)
  --dns <servers>                 DNS resolvers for VPN clients (default: 1.1.1.1, 1.0.0.1)
  --first-client <name>           Generate initial client configuration (default: client1)
  -y, --non-interactive           Run unattended using flags or sensible defaults without prompting
  --skip-packages                 Skip automatic detection and installation of OS packages
  --no-firewall                   Skip adding PostUp/PostDown iptables NAT firewall rules
  --no-start                      Do not enable or start systemd service automatically

AUTOMATED ACTIONS PERFORMED BY INIT:
  1. Detects OS distro and installs wireguard, iptables, and qrencode if missing.
  2. Detects external WAN interface and public IP automatically.
  3. Enables IPv4 sysctl packet forwarding (/etc/sysctl.d/99-wireguard-forward.conf).
  4. Generates cryptographic WireGuard server keypair (Curve25519).
  5. Configures iptables NAT masquerade forwarding rules for internet access.
  6. Creates an initial client configuration and displays its mobile QR code.
  7. Enables and starts systemd service (wg-quick@<interface>).

EXAMPLES:
  # Guided interactive wizard (recommended)
  wgctl init

  # Initialize wg1 with custom subnet
  wgctl init wg1 --subnet 10.20.30.1/24 --port 51821

  # Fully automated / headless server deployment (e.g. cloud-init, Ansible, Docker)
  wgctl init wg0 --wan eth0 --public-ip 203.0.113.1 --subnet 10.13.14.1/24 -y
HELP
      end

      def self.print_daemon_help(subcommand : String? = nil)
        case subcommand
        when "start"
          puts <<-HELP
wgctl daemon start - Start background REST API and WebSocket live metrics server

USAGE:
  wgctl daemon start [options]

OPTIONS:
  -p, --port <port>               Port to bind daemon (default: 7443)
  -H, --host <ip>                 Host IP address to bind (default: 0.0.0.0)
  --cert <file>                   Path to SSL/TLS certificate chain (enables HTTPS)
  --key <file>                    Path to SSL/TLS private key
  --cors <origin>                 Allowed CORS origin header (default: "*")

EXAMPLES:
  # Start local daemon on default port 7443
  wgctl daemon start

  # Start HTTPS daemon with custom port and certificate
  wgctl daemon start --port 7443 --cert /etc/ssl/certs/wgctl.crt --key /etc/ssl/private/wgctl.key
HELP

        when "token"
          puts <<-HELP
wgctl daemon token - Manage authentication tokens for API access

USAGE:
  wgctl daemon token <create|list|revoke> [options]

ACTIONS:
  create                          Generate a new secure Bearer token (stored with SHA-256 hash)
  list                            Display all active and expired tokens
  revoke <id|name>                Immediately revoke a token by ID or friendly name

OPTIONS:
  --name, -n <name>               Descriptive name for the token (e.g. "admin-dashboard", "mobile-app")
  --expires, -e <duration>        Token expiration duration: 7d, 30d, 90d, 1y, or never (default: 30d)

EXAMPLES:
  # Create a token valid for 90 days
  wgctl daemon token create --name "Mobile Client" --expires 90d

  # Create an administrative token that never expires
  wgctl daemon token create --name "Grafana Monitor" --expires never

  # List all tokens
  wgctl daemon token list

  # Revoke a token
  wgctl daemon token revoke "Mobile Client"
HELP

        else
          puts <<-HELP
wgctl daemon - Headless REST API and background server

USAGE:
  wgctl daemon <command> [options]

COMMANDS:
  start [options]                 Start HTTP/WebSocket REST daemon
  token create [options]          Generate a new Bearer authentication token
  token list                      List all API tokens and expiration dates
  token revoke <id|name>          Immediately revoke an API token

START OPTIONS:
  -p, --port <port>               Port to bind (default: 7443)
  -H, --host <ip>                 Host IP to bind (default: 0.0.0.0)
  --cert <file>                   Path to SSL/TLS certificate chain
  --key <file>                    Path to SSL/TLS private key
  --cors <origin>                 Allowed CORS origin (default: "*")

TOKEN OPTIONS:
  --name, -n <name>               Name for the token
  --expires, -e <duration>        Expiration: 7d, 30d, 90d, 1y, never (default: 30d)

EXAMPLES:
  wgctl daemon start --port 7443
  wgctl daemon token create --name "Web Dashboard" --expires 90d
  wgctl daemon token list
  wgctl daemon token revoke <token-id>

Run 'wgctl help daemon <start|token>' for detailed options.
HELP
        end
      end

      def self.print_status_help
        puts <<-HELP
wgctl status - Real-time interface dashboard and peer activity

USAGE:
  wgctl status [interface] [options]

ARGUMENTS:
  [interface]                     WireGuard interface to inspect (auto-detected if omitted)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --json                          Output status and peer statistics in JSON format
  -c, --config <file>             Explicit path to WireGuard configuration file

METRICS DISPLAYED:
  - Interface state (active/inactive), listening port, public key, and IP address
  - Total peer count and online peer count (handshake within last 3 minutes)
  - Friendly peer names, descriptions, assigned IPs, latest handshake, transfer Rx/Tx

EXAMPLES:
  wgctl status
  wgctl status wg0
  wgctl status -i wg0
  wgctl status wg0 --json
HELP
      end

      def self.print_check_help
        puts <<-HELP
wgctl check - Validate configuration integrity and detect conflicts

USAGE:
  wgctl check [interface] [options]

ARGUMENTS:
  [interface]                     WireGuard interface to validate

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  -c, --config <file>             Explicit path to WireGuard configuration file
  --json                          Output diagnostic results in JSON format

CHECKS PERFORMED:
  - Validates interface Address format and CIDR syntax
  - Ensures ListenPort is valid (1-65535)
  - Detects duplicate IP address allocations among peers
  - Detects duplicate public keys or invalid base64 key formats
  - Verifies PersistentKeepalive intervals

EXAMPLES:
  wgctl check
  wgctl check wg0
  wgctl check -i wg0
HELP
      end

      def self.print_apply_help
        puts <<-HELP
wgctl apply - Apply configuration to kernel live without downtime

USAGE:
  wgctl apply [interface] [options]

ARGUMENTS:
  [interface]                     WireGuard interface to synchronize (default: auto-detect)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  -c, --config <file>             Explicit path to WireGuard configuration file

HOW IT WORKS:
  Executes 'wg syncconf' using 'wg-quick strip' to sync peers and settings into
  the active WireGuard kernel interface without restarting the interface or dropping
  existing active VPN tunnels.

EXAMPLES:
  wgctl apply
  wgctl apply wg0
  wgctl apply -i wg0
HELP
      end

      def self.print_migrate_help
        puts <<-HELP
wgctl migrate - Convert legacy comments to official # wgctl:* metadata format

USAGE:
  wgctl migrate [interface] [options]

ARGUMENTS:
  [interface]                     WireGuard interface to migrate

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface (e.g. wg0, wg1)
  --dry-run                       Preview migration without modifying configuration file
  -c, --config <file>             Explicit path to WireGuard configuration file

COMPATIBILITY:
  Migrates legacy scripts (such as Nyr's wireguard-install, angristan, etc.) which use
  comments like '# BEGIN_PEER client' and '# ENDPOINT <ip>' into clean, structured
  wgctl metadata comments ('# wgctl:name=client') and '# ENDPOINT <ip>'.
  Automatic backups are created before writing.

EXAMPLES:
  wgctl migrate wg0 --dry-run
  wgctl migrate wg0
  wgctl migrate -i wg0
HELP
      end

      def self.print_interfaces_help
        puts <<-HELP
wgctl interfaces - List all discovered WireGuard network interfaces

USAGE:
  wgctl interfaces [options]

OPTIONS:
  --json                          Output interfaces list in JSON format

EXAMPLES:
  wgctl interfaces
  wgctl interfaces --json
HELP
      end

      def self.print_command_help(command : String?, subcommand : String? = nil)
        case command
        when "peer", "peers"
          print_peer_help(subcommand)
        when "client"
          print_client_help
        when "init"
          print_init_help
        when "daemon"
          print_daemon_help(subcommand)
        when "status"
          print_status_help
        when "check"
          print_check_help
        when "apply"
          print_apply_help
        when "migrate"
          print_migrate_help
        when "interfaces"
          print_interfaces_help
        when "menu", "tui"
          puts <<-HELP
wgctl menu - Interactive terminal management assistant (alias: tui)

USAGE:
  wgctl menu [interface] [options]
  wgctl                          (Launched automatically when run with no arguments in a terminal)

ARGUMENTS:
  [interface]                     WireGuard interface to manage (presents selector if omitted)

OPTIONS:
  -i, --interface <name>          Specify target WireGuard interface directly

FEATURES:
  - Guided peer management: add, edit, rename, remove
  - QR code generation and client export
  - Server initialization and migration tools
  - Diagnostic checks and live kernel sync
HELP
        else
          print_main_help
        end
      end
    end
  end
end
