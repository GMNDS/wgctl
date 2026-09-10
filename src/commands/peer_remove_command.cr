require "../cli/context"
require "../models/peer"
require "../config/writer"
require "../config/validator"
require "../wireguard/runner"

module Wgctl
  module Commands
    class PeerRemoveCommand
      def self.run(context : CLI::Context, args : Array(String))
        if args.empty?
          raise "Missing peer identifier. Usage: wgctl peer remove <name|public_key> [--dry-run]"
        end

        query = args.first
        iface = context.load_interface
        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Configuration file not found for interface #{iface.name}."
        end

        # Localizar exatamente o peer
        peer = iface.find_peer(query)
        unless peer
          raise "Peer '#{query}' not found in interface #{iface.name}."
        end

        if context.dry_run
          puts "[DRY RUN] Would remove peer '#{peer.name}' (Public Key: #{peer.public_key}, IPs: #{peer.clean_ips}) from #{iface.name}."
          return
        end

        # Remover metadata e [Peer]
        iface.peers.reject! { |p| p.public_key == peer.public_key }

        # Validar configuração restante
        report = Config::Validator.validate(iface)
        unless report.valid?
          errors = report.issues.select { |i| i.severity == Config::Severity::Error }.map(&.message).join("; ")
          raise "Validation failed after removing peer: #{errors}"
        end

        # Backup e gravação atômica
        backup_path = Config::Writer.create_backup(config_path)
        Config::Writer.save_atomically(iface, config_path, create_backup: false)

        puts "Peer '#{peer.name}' successfully removed from #{iface.name}."
        if backup_path
          puts "Backup created: #{backup_path}"
        end

        # Aplicar alteração
        if !context.no_apply && iface.active
          applied, msg = WireGuard::Runner.apply_syncconf(iface.name, config_path)
          if applied
            puts msg
          else
            puts "Warning: #{msg}"
          end
        end
      end
    end
  end
end
