require "../cli/context"
require "../models/peer"
require "../config/writer"
require "../config/validator"
require "../wireguard/runner"

module Wgctl
  module Commands
    class PeerEditCommand
      def self.run(context : CLI::Context, args : Array(String))
        if args.empty?
          raise "Missing peer identifier. Usage: wgctl peer edit <name|public_key> [options]"
        end

        query = args.first
        iface = context.load_interface
        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Configuration file not found for interface #{iface.name}."
        end

        peer = iface.find_peer(query)
        unless peer
          raise "Peer '#{query}' not found in interface #{iface.name}."
        end

        changes = [] of String

        if new_name = context.name
          new_name_clean = new_name.strip
          if new_name_clean != peer.name
            if iface.peer_exists_by_name?(new_name_clean)
              raise "Peer name '#{new_name_clean}' already exists."
            end
            changes << "name: '#{peer.name}' -> '#{new_name_clean}'"
            peer.metadata.name = new_name_clean
          end
        end

        if new_desc = context.description
          changes << "description: '#{peer.description}' -> '#{new_desc}'"
          peer.metadata.description = new_desc
        end

        if new_dev = context.device
          changes << "device: '#{peer.device}' -> '#{new_dev}'"
          peer.metadata.device = new_dev
        end

        if new_ip_arg = context.ip
          target_ip = new_ip_arg.strip
          if target_ip.downcase == "auto"
            new_ip = Config::IPAllocator.allocate_next(iface)
          elsif target_ip.includes?("/")
            new_ip = target_ip
          else
            new_ip = "#{target_ip}/32"
          end

          unless peer.allowed_ips.includes?(new_ip)
            if iface.peer_exists_by_ip?(new_ip)
              raise "IP address #{new_ip} is already assigned to another peer or interface."
            end
            changes << "allowed_ips: #{peer.allowed_ips.join(", ")} -> #{new_ip}"
            peer.allowed_ips = [new_ip]
          end
        end

        if ka = context.keepalive
          changes << "keepalive: #{peer.persistent_keepalive} -> #{ka}"
          peer.persistent_keepalive = ka
        end

        if changes.empty?
          puts "No changes specified for peer '#{peer.name}'."
          return
        end

        # Validate
        report = Config::Validator.validate(iface)
        unless report.valid?
          errors = report.issues.select { |i| i.severity == Config::Severity::Error }.map(&.message).join("; ")
          raise "Validation failed: #{errors}"
        end

        if context.dry_run
          puts "[DRY RUN] Would update peer '#{peer.name}':"
          changes.each { |c| puts "  - #{c}" }
          return
        end

        backup_path = Config::Writer.create_backup(config_path)
        Config::Writer.save_atomically(iface, config_path, create_backup: false)

        puts "Updated peer '#{peer.name}':"
        changes.each { |c| puts "  - #{c}" }
        if backup_path
          puts "Backup created: #{backup_path}"
        end

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
