require "../cli/context"
require "../models/peer"
require "../models/metadata"
require "../config/writer"
require "../config/ip_allocator"
require "../config/validator"
require "../wireguard/keys"
require "../wireguard/runner"

module Wgctl
  module Commands
    class PeerAddCommand
      def self.run(context : CLI::Context, args : Array(String))
        if args.empty?
          raise "Missing peer name. Usage: wgctl peer add <name> --ip <ip|auto> [options]"
        end

        peer_name = args.first.strip
        if peer_name.empty?
          raise "Peer name cannot be empty."
        end

        target_iface = context.interface || args[1]?

        if context.remote?
          run_remote_add(context, peer_name, target_iface)
          return
        end

        iface = context.load_interface(target_iface, hint_command: "peer add #{peer_name} --ip auto")
        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Interface configuration file not found for #{iface.name}."
        end

        # 1. Verificar se nome já existe
        if iface.peer_exists_by_name?(peer_name)
          raise "A peer with name '#{peer_name}' already exists in #{iface.name}."
        end

        # 2. Verificar e determinar IP
        ip_arg = context.ip
        if ip_arg.nil? || ip_arg.strip.empty?
          raise "Missing --ip argument. Use --ip <address> or --ip auto"
        end

        target_ip = ip_arg.strip
        if target_ip.downcase == "auto"
          allocated_ip = Config::IPAllocator.allocate_next(iface)
          puts "Assigned address: #{allocated_ip}"
        else
          # Ensure CIDR mask /32 if none provided for IPv4
          if target_ip.includes?("/")
            allocated_ip = target_ip
          else
            allocated_ip = "#{target_ip}/32"
          end

          if iface.peer_exists_by_ip?(allocated_ip)
            raise "IP address #{allocated_ip} is already assigned to another peer or the interface."
          end
        end

        # 3. Gerar private/public key
        client_private_key = WireGuard::Keys.generate_private_key
        client_public_key = WireGuard::Keys.public_key(client_private_key)

        # Opcional pre-shared key
        psk : String? = nil
        if context.preshared_key
          psk = WireGuard::Keys.generate_preshared_key
        end

        # 4. Adicionar [Peer] ao servidor
        metadata = Models::Metadata.new(
          name: peer_name,
          description: context.description,
          device: context.device,
          client_private_key: client_private_key
        )

        new_peer = Models::Peer.new(
          public_key: client_public_key,
          allowed_ips: [allocated_ip],
          metadata: metadata,
          preshared_key: psk,
          persistent_keepalive: context.keepalive
        )

        iface.peers << new_peer

        # Validar antes de salvar
        report = Config::Validator.validate(iface)
        unless report.valid?
          errors = report.issues.select { |i| i.severity == Config::Severity::Error }.map(&.message).join("; ")
          raise "Validation failed: #{errors}"
        end

        if context.dry_run
          puts "[DRY RUN] Peer '#{peer_name}' would be added with IP #{allocated_ip} and public key #{client_public_key}"
          return
        end

        # Salvar atomicamente com backup
        backup_path = Config::Writer.create_backup(config_path)
        Config::Writer.save_atomically(iface, config_path, create_backup: false)

        puts "Peer '#{peer_name}' added successfully to #{iface.name}."
        if backup_path
          puts "Backup created: #{backup_path}"
        end

        # 5. Aplicar a configuração se ativa
        if !context.no_apply && iface.active
          applied, msg = WireGuard::Runner.apply_syncconf(iface.name, config_path)
          if applied
            puts msg
          else
            puts "Warning: #{msg}"
          end
        end

        puts ""
        puts "To generate client configuration, run:"
        puts "  wgctl client #{peer_name}"
        puts "  wgctl client #{peer_name} --qr"
      end

      private def self.run_remote_add(context : CLI::Context, peer_name : String, target_iface : String?)
        client = context.remote_client
        iface_name = target_iface || context.interface || begin
          ifaces = client.list_interfaces
          ifaces.first? || "wg0"
        end

        payload = Hash(String, String | Int32 | Nil){
          "name" => peer_name,
          "ip" => context.ip || "auto",
          "description" => context.description,
          "device" => context.device,
          "keepalive" => context.keepalive
        }

        puts "Adding peer '#{peer_name}' to remote interface '#{iface_name}'..."
        result = client.add_peer(iface_name, payload)

        assigned_ip = result["allowed_ips"]?.try(&.as_a.first?.try(&.as_s)) || "allocated"
        pub_key = result["public_key"]?.try(&.as_s) || ""

        puts "✓ Peer '#{peer_name}' added successfully!"
        puts "Assigned IP: #{assigned_ip}"
        puts "Public key:  #{pub_key}"

        if qr = result["qr_text"]?.try(&.as_s?)
          puts "\n#{qr}"
        end

        puts ""
        puts "To fetch client configuration:"
        puts "  wgctl client #{peer_name}"
        puts "  wgctl client #{peer_name} --qr"
      end
    end
  end
end
