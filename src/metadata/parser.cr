require "../models/metadata"

module Wgctl
  module MetadataHandler
    class Parser
      # Parses metadata key-values from a collection of comments
      def self.parse(lines : Array(String)) : Models::Metadata
        metadata = Models::Metadata.new
        lines.each do |line|
          Models::Metadata.parse_line(line, metadata)
        end
        metadata
      end

      # Checks if a line is a wgctl metadata comment
      def self.metadata_line?(line : String) : Bool
        (line.strip =~ /^#\s*wgctl:[a-zA-Z0-9_\-]+=/ ? true : false)
      end
    end
  end
end
