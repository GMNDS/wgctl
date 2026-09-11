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

        query = args.first
        iface = context.load_interface

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
        ipv4 = iface.address.find { |a| a.includes?(".") }
        return "0.0.0.0/0, ::/0" unless ipv4

        parts = ipv4.split("/")
        ip_str = parts[0]
        prefix = parts.size > 1 ? parts[1].to_i? || 24 : 24

        octets = ip_str.split(".").map(&.to_u32)
        return "0.0.0.0/0" if octets.size != 4

        ip_int = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        mask = prefix == 0 ? 0_u32 : (~0_u32 << (32 - prefix)) & 0xFFFFFFFF_u32
        net_int = ip_int & mask

        o1 = (net_int >> 24) & 0xFF
        o2 = (net_int >> 16) & 0xFF
        o3 = (net_int >> 8) & 0xFF
        o4 = net_int & 0xFF

        "#{o1}.#{o2}.#{o3}.#{o4}/#{prefix}"
      rescue
        "0.0.0.0/0"
      end
    end
  end
end
