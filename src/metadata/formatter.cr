require "../models/metadata"

module Wgctl
  module MetadataHandler
    class Formatter
      # Formats metadata into WireGuard comments
      def self.format(metadata : Models::Metadata) : Array(String)
        metadata.to_comments
      end
    end
  end
end
