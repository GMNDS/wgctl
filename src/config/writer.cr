require "file_utils"
require "../models/interface"
require "../models/peer"
require "../metadata/formatter"

module Wgctl
  module Config
    class Writer
      # Emits wireguard configuration text
      def self.format(iface : Models::Interface) : String
        io = IO::Memory.new

        # Ensure server_endpoint is kept as comment
        has_ep_comment = iface.raw_headers.any? { |h| h.strip =~ /^#\s*(ENDPOINT|wgctl:endpoint=)/i }
        if (ep = iface.server_endpoint) && !has_ep_comment
          io.puts "# ENDPOINT #{ep}"
        end

        # Top comments / headers
        iface.raw_headers.each do |h|
          io.puts h
        end

        io.puts "[Interface]"
        if pk = iface.private_key
          io.puts "PrivateKey = #{pk}"
        end

        unless iface.address.empty?
          io.puts "Address = #{iface.address.join(", ")}"
        end

        if lp = iface.listen_port
          io.puts "ListenPort = #{lp}"
        end

        # Raw properties for Interface (DNS, PostUp, PostDown, etc.)
        iface.raw_properties.each do |key, values|
          next if key.downcase == "endpoint" # Endpoint is not an [Interface] directive!
          values.each do |val|
            io.puts "#{key} = #{val}"
          end
        end

        # Peers
        iface.peers.each do |peer|
          io.puts ""

          # Write non-wgctl comments
          peer.raw_comments.each do |comm|
            io.puts comm
          end

          # Write wgctl metadata comments
          MetadataHandler::Formatter.format(peer.metadata).each do |meta_line|
            io.puts meta_line
          end

          io.puts "[Peer]"
          io.puts "PublicKey = #{peer.public_key}"
          if psk = peer.preshared_key
            io.puts "PresharedKey = #{psk}"
          end
          unless peer.allowed_ips.empty?
            io.puts "AllowedIPs = #{peer.allowed_ips.join(", ")}"
          end
          if ep = peer.endpoint
            io.puts "Endpoint = #{ep}"
          end
          if ka = peer.persistent_keepalive
            io.puts "PersistentKeepalive = #{ka}"
          end

          peer.raw_properties.each do |k, v|
            io.puts "#{k} = #{v}"
          end
        end

        io.to_s
      end

      # Creates a backup before saving
      # Example: /etc/wireguard/backups/wg0.conf.2026-09-10T135400
      def self.create_backup(filepath : String) : String?
        return nil unless File.exists?(filepath)

        dir = File.dirname(File.expand_path(filepath))
        filename = File.basename(filepath)
        backup_dir = File.join(dir, "backups")

        Dir.mkdir_p(backup_dir) unless Dir.exists?(backup_dir)

        timestamp = Time.local.to_s("%Y-%m-%dT%H%M%S")
        backup_file = File.join(backup_dir, "#{filename}.#{timestamp}")

        FileUtils.cp(filepath, backup_file)
        # Ensure 0600 permissions
        File.chmod(backup_file, 0o600)
        backup_file
      rescue ex
        # If unable to create backup (e.g., read-only filesystem or permission), report warning
        nil
      end

      # Atomically saves configuration to disk with 0600 permissions and optional backup
      def self.save_atomically(iface : Models::Interface, filepath : String, create_backup : Bool = true) : String
        content = format(iface)

        if create_backup && File.exists?(filepath)
          create_backup(filepath)
        end

        dir = File.dirname(File.expand_path(filepath))
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        # Create temporary file in same directory so rename is atomic (same filesystem)
        temp_filename = ".#{File.basename(filepath)}.tmp.#{Process.pid}.#{Random.rand(100000)}"
        temp_path = File.join(dir, temp_filename)

        File.write(temp_path, content)
        File.chmod(temp_path, 0o600)

        # Atomic replacement
        {% if flag?(:windows) %}
          File.delete(filepath) if File.exists?(filepath)
        {% end %}
        File.rename(temp_path, filepath)

        filepath
      ensure
        # Cleanup temporary file if something crashed
        if temp_path && File.exists?(temp_path)
          File.delete(temp_path) rescue nil
        end
      end
    end
  end
end
