require "../models/interface"
require "../models/runtime_peer"

module Wgctl
  module WireGuard
    class DumpParser
      # Parses `wg show <interface> dump` output and enriches the Interface and its Peers
      def self.parse(output : String, iface : Models::Interface)
        lines = output.lines.map(&.strip).reject(&.empty?)
        return if lines.empty?

        # Line 0: Interface info
        iface_cols = lines[0].split('\t')
        if iface_cols.size >= 3
          # iface_cols[0] is private key
          iface.runtime_public_key = iface_cols[1] unless iface_cols[1] == "(none)"
          iface.runtime_listen_port = iface_cols[2].to_i?
          iface.active = true
        end

        # Lines 1..N: Peer info
        runtime_peers_by_key = Hash(String, Models::RuntimePeer).new

        lines[1..].each do |line|
          cols = line.split('\t')
          next if cols.size < 8

          pubkey = cols[0].strip
          psk = cols[1].strip == "(none)" ? nil : cols[1].strip
          endpoint = cols[2].strip == "(none)" ? nil : cols[2].strip
          allowed_ips = cols[3].strip == "(none)" ? [] of String : cols[3].split(",").map(&.strip).reject(&.empty?)
          handshake = cols[4].strip.to_i64? || 0_i64
          rx = cols[5].strip.to_u64? || 0_u64
          tx = cols[6].strip.to_u64? || 0_u64
          keepalive = cols[7].strip == "off" ? nil : cols[7].strip.to_i?

          rp = Models::RuntimePeer.new(
            public_key: pubkey,
            preshared_key: psk,
            endpoint: endpoint,
            allowed_ips: allowed_ips,
            latest_handshake_epoch: handshake,
            transfer_rx: rx,
            transfer_tx: tx,
            persistent_keepalive: keepalive
          )

          runtime_peers_by_key[pubkey] = rp
        end

        # Match runtime peers to existing peers in interface config
        iface.peers.each do |peer|
          if rp = runtime_peers_by_key[peer.public_key]?
            peer.runtime = rp
            runtime_peers_by_key.delete(peer.public_key)
          end
        end

        # If there are active peers in runtime that were not in the config file,
        # add them as unmanaged peers so they still appear in status
        runtime_peers_by_key.each do |pubkey, rp|
          unmanaged_peer = Models::Peer.new(
            public_key: pubkey,
            allowed_ips: rp.allowed_ips,
            endpoint: rp.endpoint,
            runtime: rp
          )
          iface.peers << unmanaged_peer
        end
      end
    end
  end
end
