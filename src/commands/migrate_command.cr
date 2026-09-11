require "../cli/context"
require "../config/writer"
require "../config/validator"

module Wgctl
  module Commands
    class MigrateCommand
      def self.run(context : CLI::Context, args : Array(String))
        target_name = context.interface || args.first?
        iface = context.load_interface(target_name, hint_command: "migrate")
        config_path = iface.config_path
        unless config_path && File.exists?(config_path)
          raise "Configuration file not found for #{iface.name}."
        end

        migrated_count = 0

        iface.peers.each do |peer|
          # Remove any legacy lines like # BEGIN_PEER or # END_PEER from raw_comments
          peer.raw_comments.reject! do |c|
            s = c.strip
            s =~ /^#\s*BEGIN_PEER\s+/ || s =~ /^#\s*END_PEER\s+/
          end

          # If the peer now has a name but didn't have wgctl metadata before,
          # it will now be written out as # wgctl:name=<name>!
          if peer.has_name?
            migrated_count += 1
          end
        end

        if context.dry_run
          puts "[DRY RUN] Would migrate #{migrated_count} peers in #{iface.name} to official # wgctl:* metadata format."
          return
        end

        backup_path = Config::Writer.create_backup(config_path)
        Config::Writer.save_atomically(iface, config_path, create_backup: false)

        puts "Successfully migrated #{migrated_count} peers in #{iface.name} to # wgctl:* format."
        if backup_path
          puts "Backup created: #{backup_path}"
        end
      end
    end
  end
end
