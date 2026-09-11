module Wgctl
  module Commands
    class VersionCommand
      VERSION = "0.2.1"

      def self.run
        puts "wgctl version #{VERSION}"
      end
    end
  end
end
