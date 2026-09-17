require "../cli/context"
require "../models/peer"
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
            _, qr_text = client.get_peer_qr(iface_name, query)
            if qr_text
              puts qr_text
            else
              puts "QR code not available from server. Falling back to terminal generation:"
              conf = client.get_client_config(iface_name, query)
              puts WireGuard::Runner.generate_qr_terminal(conf)
            end
          else
            output_str = client.get_client_config(iface_name, query)
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
        client_priv = peer.metadata.client_private_key
        if client_priv.nil? || client_priv.strip.empty?
          client_priv = "<REPLACE_WITH_CLIENT_PRIVATE_KEY>"
        end

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
        allowed_ips = calculate_client_allowed_ips(iface)

        # Build client configuration
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

        output_str = client_conf.to_s

        # Handle options
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

      private def self.detect_endpoint(iface : Models::Interface, port : Int32) : String
        # Check if an explicit server endpoint is set in Interface
        if custom_ep = iface.endpoint
          return custom_ep.includes?(":") ? custom_ep : "#{custom_ep}:#{port}"
        end

        # Try to resolve hostname
        host = System.hostname rescue "vpn.example.com"
        "#{host}:#{port}"
      end

      private def self.calculate_client_allowed_ips(iface : Models::Interface) : String
        "0.0.0.0/0, ::/0"
      end
    end
  end
end
