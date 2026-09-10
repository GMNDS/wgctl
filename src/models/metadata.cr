require "json"

module Wgctl
  module Models
    class Metadata
      include JSON::Serializable

      property name : String?
      property description : String?
      property device : String?
      property client_private_key : String?
      property extra : Hash(String, String) = Hash(String, String).new

      def initialize(
        @name : String? = nil,
        @description : String? = nil,
        @device : String? = nil,
        @client_private_key : String? = nil,
        @extra : Hash(String, String) = Hash(String, String).new
      )
      end

      def empty? : Bool
        @name.nil? && @description.nil? && @device.nil? && @client_private_key.nil? && @extra.empty?
      end

      # Serializes metadata into WireGuard comment lines
      # Example:
      # # wgctl:name=asteri-c
      # # wgctl:description=Contabo Germany
      # # wgctl:device=server
      def to_comments : Array(String)
        lines = [] of String
        lines << "# wgctl:name=#{@name}" if @name
        lines << "# wgctl:description=#{@description}" if @description
        lines << "# wgctl:device=#{@device}" if @device
        lines << "# wgctl:client_private_key=#{@client_private_key}" if @client_private_key
        @extra.each do |k, v|
          lines << "# wgctl:#{k}=#{v}"
        end
        lines
      end

      def self.parse_line(line : String, metadata : Metadata) : Bool
        trimmed = line.strip
        if trimmed =~ /^#\s*wgctl:([a-zA-Z0-9_\-]+)=(.*)$/
          key = $1.strip
          value = $2.strip
          case key
          when "name"
            metadata.name = value
          when "description"
            metadata.description = value
          when "device"
            metadata.device = value
          when "client_private_key"
            metadata.client_private_key = value
          else
            metadata.extra[key] = value
          end
          true
        else
          false
        end
      end
    end
  end
end
