require "../cli/context"
require "../models/peer"
require "../config/writer"
require "../config/validator"
require "../config/allowed_ips"
require "../wireguard/keys"
require "../wireguard/runner"

module Wgctl
  module Commands
    class ClientCommand
      def self.run(context : CLI::Context, args : Array(String))
        if args.empty?
          raise "Missing peer identifier. Usage: wgctl client <name|public_key> [options]"
        end

        query = args[0]
        target_iface = context.interface || args[1]?

        if context.remote?
          client = context.remote_client
          iface_name = target_iface || context.interface || client.list_interfaces.first? || "wg0"

          if context.qr_code
            _, qr_text = client.get_peer_qr(iface_name, query, context.client_allowed_ips)
            if qr_text
              puts qr_text
            else
              puts "QR code not available from server. Falling back to terminal generation:"
              conf = client.get_client_config(iface_name, query, context.client_allowed_ips)
              puts WireGuard::Runner.generate_qr_terminal(conf)
            end
          else
            output_str = client.get_client_config(iface_name, query, context.client_allowed_ips)
            if out_path = context.output_file
              File.write(out_path, output_str)
              File.chmod(out_path, 0o600)
              puts "Client configuration written to: #{out_path} (mode 0600)"
            else
              print output_str
            end
          end
          return
        end

        iface = context.load_interface(target_iface, hint_command: "client #{query}")

        peer = iface.find_peer(query)
        unless peer
          raise "Peer '#{query}' not found in interface #{iface.name}."
        end

        # Determine client private key
        client_priv : String

        if context.rotate
          # Zero-knowledge: the server does not store client private keys, so
          # regeneration means issuing a fresh keypair and updating the peer's
          # public key on the server (with backup + live sync).
          client_priv = rotate_peer_keys(iface, peer, context)
        else
          client_priv = peer.metadata.client_private_key || ""
          if client_priv.strip.empty?
            STDERR.puts "Note: the client private key is not stored on the server (zero-knowledge)."
            STDERR.puts "Run 'wgctl client #{peer.name} --rotate' to generate a new keypair and update the server."
            client_priv = "<REPLACE_WITH_CLIENT_PRIVATE_KEY>"
          end
        end

        output_str = render_client_config(iface, peer, context, client_priv)

        if out_path = context.output_file
          File.write(out_path, output_str)
          # Strict 0600 permissions
          File.chmod(out_path, 0o600)
          puts "Client configuration written to: #{out_path} (mode 0600)"
        elsif context.qr_code
          qr = WireGuard::Runner.generate_qr_terminal(output_str)
          puts qr
        else
          print output_str
        end
      end

      # Builds the client `.conf` content. `client_priv` is passed explicitly so
      # callers can render a freshly generated key that is never persisted.
      def self.render_client_config(
        iface : Models::Interface,
        peer : Models::Peer,
        context : CLI::Context,
        client_priv : String,
        explicit_allowed_ips : String? = nil
      ) : String
        # Determine server public key
        server_pub = iface.runtime_public_key
        if (server_pub.nil? || server_pub.empty?) && iface.private_key
          server_pub = WireGuard::Keys.public_key(iface.private_key.not_nil!) rescue nil
        end
        server_pub ||= "<SERVER_PUBLIC_KEY>"

        # Determine server endpoint
        server_port = iface.effective_listen_port || 51820
        endpoint = context.endpoint || detect_endpoint(iface, server_port)

        # Determine AllowedIPs for client
        allowed_ips = calculate_client_allowed_ips(iface, peer, explicit_allowed_ips || context.client_allowed_ips)

        client_conf = IO::Memory.new
        client_conf.puts "[Interface]"
        client_conf.puts "PrivateKey = #{client_priv}"
        client_conf.puts "Address = #{peer.clean_ips}"
        if dns = iface.raw_properties["DNS"]?.try(&.join(", "))
          client_conf.puts "DNS = #{dns}"
        end
        client_conf.puts ""
        client_conf.puts "[Peer]"
        client_conf.puts "PublicKey = #{server_pub}"
        client_conf.puts "Endpoint = #{endpoint}"
        client_conf.puts "AllowedIPs = #{allowed_ips}"
        keepalive = peer.persistent_keepalive || 25
        client_conf.puts "PersistentKeepalive = #{keepalive}"
        client_conf.to_s
      end

      # Generates a fresh keypair, replaces the peer public key on the server and
      # applies the change live. Returns the new client private key.
      private def self.rotate_peer_keys(iface : Models::Interface, peer : Models::Peer, context : CLI::Context) : String
        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Interface configuration file not found for #{iface.name}."
        end

        new_priv = WireGuard::Keys.generate_private_key
        new_pub = WireGuard::Keys.public_key(new_priv)
        old_pub = peer.public_key

        peer.public_key = new_pub
        peer.metadata.client_private_key = nil

        report = Config::Validator.validate(iface)
        unless report.valid?
          errors = report.issues.select { |i| i.severity == Config::Severity::Error }.map(&.message).join("; ")
          raise "Key rotation failed validation: #{errors}"
        end

        backup_path = Config::Writer.create_backup(config_path)
        Config::Writer.save_atomically(iface, config_path, create_backup: false)

        if !context.no_apply && iface.active
          applied, msg = WireGuard::Runner.apply_syncconf(iface.name, config_path)
          puts msg if applied
          STDERR.puts "Warning: #{msg}" unless applied
        end

        STDERR.puts "Rotated keys for peer '#{peer.name}': #{short(old_pub)} -> #{short(new_pub)}"
        STDERR.puts "Backup created: #{backup_path}" if backup_path
        new_priv
      end

      private def self.short(key : String) : String
        "#{key[0, Math.min(8, key.size)]}..."
      end

      private def self.detect_endpoint(iface : Models::Interface, port : Int32) : String
        # Check if an explicit server endpoint is set in Interface
        if custom_ep = iface.endpoint
          return custom_ep.includes?(":") ? custom_ep : "#{custom_ep}:#{port}"
        end

        # Try to resolve hostname
        host = System.hostname rescue "vpn.example.com"
        "#{host}:#{port}"
      end

      def self.calculate_client_allowed_ips(iface : Models::Interface, peer : Models::Peer? = nil, explicit : String? = nil) : String
        Config::AllowedIPs.resolve(iface, peer, explicit)
      end
    end
  end
end
