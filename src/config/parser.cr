require "../models/interface"
require "../models/peer"
require "../models/metadata"
require "../metadata/parser"

module Wgctl
  module Config
    class Parser
      def self.parse_file(filepath : String, interface_name : String? = nil) : Models::Interface
        content = File.read(filepath)
        iface_name = interface_name || File.basename(filepath, ".conf")
        parse_string(content, iface_name, filepath)
      end

      def self.parse_string(content : String, interface_name : String, config_path : String? = nil) : Models::Interface
        lines = content.lines

        iface = Models::Interface.new(name: interface_name, config_path: config_path)

        current_section : String? = nil
        pending_comments = [] of String
        pending_metadata = Models::Metadata.new

        # Peer currently being constructed
        current_peer : Models::Peer? = nil

        lines.each do |line|
          stripped = line.strip

          # Comment line
          if stripped.starts_with?("#") || stripped.starts_with?(";")
            if MetadataHandler::Parser.metadata_line?(line)
              Models::Metadata.parse_line(line, pending_metadata)
            else
              # Check for Nyr legacy peer format: # BEGIN_PEER <client>
              if stripped =~ /^#\s*BEGIN_PEER\s+(.+)$/
                legacy_client = $1.strip
                if pending_metadata.name.nil? || pending_metadata.name.to_s.empty?
                  pending_metadata.name = legacy_client
                end
              elsif stripped =~ /^#\s*ENDPOINT\s+(.+)$/
                # Nyr legacy server endpoint comment
                ep = $1.strip
                iface.raw_properties["Endpoint"] ||= [] of String
                iface.raw_properties["Endpoint"] << ep
              end
              pending_comments << line
            end
            next
          end

          # Empty line
          if stripped.empty?
            # If we are not in a section or between peers, keep blank lines in comments
            if current_peer.nil? && current_section.nil?
              pending_comments << line
            elsif current_peer.nil? && current_section == "interface"
              # Could be blank line in [Interface]
            end
            next
          end

          # Section header
          if stripped =~ /^\[\s*([a-zA-Z0-9_-]+)\s*\]$/
            section_name = $1.downcase

            if current_peer
              # Finish previous peer
              iface.peers << current_peer
              current_peer = nil
            end

            current_section = section_name

            if section_name == "interface"
              iface.raw_headers = pending_comments.dup
              pending_comments.clear
              pending_metadata = Models::Metadata.new
            elsif section_name == "peer"
              current_peer = Models::Peer.new(
                public_key: "",
                metadata: pending_metadata,
                raw_comments: pending_comments.dup
              )
              pending_comments.clear
              pending_metadata = Models::Metadata.new
            end
            next
          end

          # Key = Value
          if stripped =~ /^([^=]+)=(.*)$/
            key = $1.strip
            value = $2.strip

            case current_section
            when "interface"
              case key.downcase
              when "address"
                # Handle comma-separated addresses
                value.split(",").map(&.strip).reject(&.empty?).each do |addr|
                  iface.address << addr
                end
              when "listenport"
                iface.listen_port = value.to_i?
              when "privatekey"
                iface.private_key = value
              else
                # Other interface properties (DNS, PostUp, PostDown, SaveConfig, etc.)
                iface.raw_properties[key] ||= [] of String
                iface.raw_properties[key] << value
              end

            when "peer"
              if current_peer
                case key.downcase
                when "publickey"
                  current_peer.public_key = value
                when "allowedips"
                  value.split(",").map(&.strip).reject(&.empty?).each do |ip|
                    current_peer.allowed_ips << ip
                  end
                when "endpoint"
                  current_peer.endpoint = value
                when "presharedkey"
                  current_peer.preshared_key = value
                when "persistentkeepalive"
                  current_peer.persistent_keepalive = value.to_i?
                else
                  current_peer.raw_properties[key] = value
                end
              end
            end
          end
        end

        if current_peer
          iface.peers << current_peer
        end

        iface
      end
    end
  end
end
