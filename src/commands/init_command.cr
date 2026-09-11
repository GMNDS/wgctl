require "../cli/context"
require "../models/interface"
require "../models/peer"
require "../models/metadata"
require "../config/writer"
require "../wireguard/keys"
require "../wireguard/system_detector"
require "../wireguard/firewall_manager"
require "../wireguard/sysctl_manager"
require "../wireguard/service_manager"
require "../wireguard/runner"
require "../wireguard/package_manager"

module Wgctl
  module Commands
    class InitCommand
      def self.run(context : CLI::Context, args : Array(String))
        interface_name = context.interface || args.first? || "wg0"
        config_path = context.config_file || "/etc/wireguard/#{interface_name}.conf"

        if File.exists?(config_path) && !context.dry_run
          puts "Configuration file '#{config_path}' already exists."
          print "Do you want to overwrite it? (all existing peers will be lost) [y/N]: "
          STDOUT.flush
          ans = gets.to_s.strip.downcase
          unless ans == "y" || ans == "yes"
            puts "Initialization aborted."
            return
          end
        end

        interactive = STDIN.tty? && !context.non_interactive

        puts "=================================================="
        puts "  wgctl Server Initialization (#{interface_name})"
        puts "=================================================="
        puts ""

        # 0. Check and install system packages if missing
        unless context.skip_pkg_install || context.dry_run
          missing = WireGuard::PackageManager.missing_tools
          if missing.empty?
            puts "✓ System dependencies already installed (wireguard-tools, iptables, qrencode)"
          else
            puts "Missing required system packages: #{missing.join(", ")}"
            distro = WireGuard::PackageManager.detect_distro
            if distro == :unknown
              puts "Note: Could not automatically detect Linux distribution. Please install #{missing.join(", ")} manually."
            else
              should_install = true
              if interactive
                print "Install missing system packages automatically using your package manager? [Y/n]: "
                STDOUT.flush
                input = gets.to_s.strip.downcase
                should_install = (input.empty? || input == "y" || input == "yes")
              end

              if should_install
                puts "Installing system dependencies..."
                success, msg = WireGuard::PackageManager.install_dependencies(inherit_output: true)
                if success
                  puts "✓ #{msg}"
                else
                  puts "Warning: #{msg}"
                end
              end
            end
          end
          puts ""
        end

        # 1. Detect and resolve WAN Interface
        detected_wan = WireGuard::SystemDetector.detect_default_wan_interface
        wan_iface = context.wan_interface || detected_wan
        if interactive && context.wan_interface.nil?
          print "Default external network interface [#{detected_wan}]: "
          STDOUT.flush
          input = gets.to_s.strip
          wan_iface = input unless input.empty?
        end

        # 2. Detect and resolve Public IP
        detected_ip = WireGuard::SystemDetector.detect_public_ip
        public_ip = context.public_ip || detected_ip
        if interactive && context.public_ip.nil?
          print "Server public IPv4 address or hostname [#{detected_ip}]: "
          STDOUT.flush
          input = gets.to_s.strip
          public_ip = input unless input.empty?
        end

        # 3. Resolve Port
        port = context.port || 51820
        if interactive && context.port.nil?
          print "WireGuard listen port [51820]: "
          STDOUT.flush
          input = gets.to_s.strip
          port = input.to_i? || 51820 unless input.empty?
        end

        # 4. Resolve Subnet
        subnet = context.subnet || "10.13.14.1/24"
        if interactive && context.subnet.nil?
          print "Server internal VPN address / subnet [10.13.14.1/24]: "
          STDOUT.flush
          input = gets.to_s.strip
          subnet = input unless input.empty?
        end

        # 5. Resolve Client DNS
        dns = context.dns || "1.1.1.1, 1.0.0.1"
        if interactive && context.dns.nil?
          puts ""
          puts "Select DNS server for VPN clients:"
          puts "  1) Cloudflare (1.1.1.1, 1.0.0.1)"
          puts "  2) Google (8.8.8.8, 8.8.4.4)"
          puts "  3) Quad9 (9.9.9.9, 149.112.112.112)"
          puts "  4) AdGuard (94.140.14.14, 94.140.15.15)"
          puts "  5) Internal Server Gateway (#{subnet.split("/").first})"
          print "Option [1]: "
          STDOUT.flush
          dns_choice = gets.to_s.strip
          case dns_choice
          when "2"
            dns = "8.8.8.8, 8.8.4.4"
          when "3"
            dns = "9.9.9.9, 149.112.112.112"
          when "4"
            dns = "94.140.14.14, 94.140.15.15"
          when "5"
            dns = subnet.split("/").first
          else
            dns = "1.1.1.1, 1.0.0.1"
          end
        end

        # 6. Ask for First Client Name
        first_client_name = context.first_client
        if interactive && first_client_name.nil?
          puts ""
          print "Create an initial client config? Enter name (or press Enter to skip) [client1]: "
          STDOUT.flush
          input = gets.to_s.strip
          first_client_name = input.empty? ? "client1" : input
        end

        puts ""
        puts "Initializing WireGuard server configuration..."

        # Generate Server Keys
        server_priv = WireGuard::Keys.generate_private_key
        server_pub = WireGuard::Keys.public_key(server_priv)

        iface = Models::Interface.new(
          name: interface_name,
          config_path: config_path,
          address: [subnet],
          listen_port: port,
          private_key: server_priv,
          server_endpoint: "#{public_ip}:#{port}"
        )
        iface.raw_headers << "# ENDPOINT #{public_ip}:#{port}"
        iface.raw_properties["DNS"] = [dns]

        # Add NAT forwarding rules
        unless context.no_firewall
          post_up = WireGuard::FirewallManager.generate_post_up(wan_iface)
          post_down = WireGuard::FirewallManager.generate_post_down(wan_iface)
          iface.raw_properties["PostUp"] = [post_up]
          iface.raw_properties["PostDown"] = [post_down]
        end

        first_client_conf_str : String? = nil
        first_client_target_file : String? = nil

        # Generate First Client if requested
        if client_name = first_client_name
          clean_client_name = client_name.gsub(/[^a-zA-Z0-9_\-]/, "_")
          client_priv = WireGuard::Keys.generate_private_key
          client_pub = WireGuard::Keys.public_key(client_priv)

          # First peer IP is gateway + 1 (e.g. 10.13.14.2/32)
          parts = subnet.split("/")
          base_octets = parts[0].split(".")
          client_ip = "#{base_octets[0]}.#{base_octets[1]}.#{base_octets[2]}.2/32"

          client_meta = Models::Metadata.new(
            name: clean_client_name,
            description: "Initial client",
            device: "mobile",
            client_private_key: client_priv
          )

          peer = Models::Peer.new(
            public_key: client_pub,
            allowed_ips: [client_ip],
            metadata: client_meta,
            persistent_keepalive: 25
          )
          iface.peers << peer

          # Build client configuration string
          c_conf = IO::Memory.new
          c_conf.puts "[Interface]"
          c_conf.puts "PrivateKey = #{client_priv}"
          c_conf.puts "Address = #{client_ip}"
          c_conf.puts "DNS = #{dns}"
          c_conf.puts ""
          c_conf.puts "[Peer]"
          c_conf.puts "PublicKey = #{server_pub}"
          c_conf.puts "Endpoint = #{public_ip}:#{port}"
          c_conf.puts "AllowedIPs = 0.0.0.0/0, ::/0"
          c_conf.puts "PersistentKeepalive = 25"
          first_client_conf_str = c_conf.to_s
          first_client_target_file = File.join(Dir.current, "#{clean_client_name}.conf")
        end

        if context.dry_run
          puts "[DRY RUN] Would write server configuration to #{config_path}:"
          puts "--------------------------------------------------"
          puts Config::Writer.format(iface)
          puts "--------------------------------------------------"
          if first_client_conf_str
            puts "[DRY RUN] Would create client config #{first_client_target_file}:"
            puts first_client_conf_str
          end
          return
        end

        # Save server config atomically with 0600 mode
        Config::Writer.save_atomically(iface, config_path, create_backup: true)
        puts "✓ Server configuration written to #{config_path} (mode 0600)"

        # Enable sysctl IP forwarding
        success_fw, msg_fw = WireGuard::SysctlManager.enable_forwarding
        if success_fw
          puts "✓ #{msg_fw}"
        else
          puts "Warning: #{msg_fw}"
        end

        # Enable and start systemd service
        unless context.no_start
          success_svc, msg_svc = WireGuard::ServiceManager.enable_and_start(interface_name)
          if success_svc
            puts "✓ #{msg_svc}"
          else
            puts "Note: #{msg_svc} (interface can be started manually with 'wg-quick up #{interface_name}')"
          end
        end

        # Save first client file if generated
        if first_client_conf_str && first_client_target_file
          File.write(first_client_target_file, first_client_conf_str)
          File.chmod(first_client_target_file, 0o600)
          puts "✓ Client configuration written to #{first_client_target_file} (mode 0600)"

          puts ""
          puts "=================================================="
          puts "  Client QR Code (scan with WireGuard mobile app)"
          puts "=================================================="
          puts ""
          begin
            qr = WireGuard::Runner.generate_qr_terminal(first_client_conf_str)
            puts qr
          rescue ex
            puts "Note: Install 'qrencode' to view terminal QR codes (#{ex.message})"
          end
        end

        puts ""
        puts "=================================================="
        puts "  WireGuard server '#{interface_name}' successfully configured!"
        puts "  Run 'wgctl status' to view live peers"
        puts "  Run 'wgctl' or 'wgctl menu' to launch interactive management"
        puts "=================================================="
      end
    end
  end
end
