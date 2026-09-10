require "../cli/context"
require "../output/formatter"
require "../output/json_formatter"

module Wgctl
  module Commands
    class PeerShowCommand
      def self.run(context : CLI::Context, args : Array(String))
        if args.empty?
          raise "Missing peer name or public key. Usage: wgctl peer show <name|public_key>"
        end

        query = args.first
        iface = context.load_interface

        peer = iface.find_peer(query)
        unless peer
          raise "Peer '#{query}' not found in interface #{iface.name}."
        end

        if context.json_output
          puts Output::JsonFormatter.format_peer_show(peer)
        else
          puts Output::Formatter.format_peer_show(peer)
        end
      end
    end
  end
end
