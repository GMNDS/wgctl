module Wgctl
  module Commands
    class VersionCommand
      VERSION = "0.6.3"

      def self.run
        puts "wgctl version #{VERSION}"
      end
    end
  end
end
