module Wgctl
  module Commands
    class VersionCommand
      VERSION = "0.3.3"

      def self.run
        puts "wgctl version #{VERSION}"
      end
    end
  end
end
