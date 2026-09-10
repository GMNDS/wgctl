require "json"
require "../models/interface"
require "../models/peer"
require "../config/validator"

module Wgctl
  module Output
    class JsonFormatter
      def self.format_status(iface : Models::Interface) : String
        data = {
          "interface" => iface.name,
          "address" => iface.effective_address,
          "listen_port" => iface.effective_listen_port,
          "active" => iface.active,
          "peers" => iface.peers.map do |p|
            {
              "name" => p.name,
              "description" => p.description,
              "device" => p.device,
              "public_key" => p.public_key,
              "allowed_ips" => p.allowed_ips,
              "endpoint" => p.effective_endpoint,
              "handshake" => p.effective_handshake,
              "latest_handshake_epoch" => p.runtime.try(&.latest_handshake_epoch) || 0_i64,
              "rx_bytes" => p.runtime.try(&.transfer_rx) || 0_u64,
              "tx_bytes" => p.runtime.try(&.transfer_tx) || 0_u64,
              "rx_formatted" => p.effective_rx,
              "tx_formatted" => p.effective_tx,
              "online" => p.online?
            }
          end
        }
        data.to_pretty_json
      end

      def self.format_peers(iface : Models::Interface) : String
        data = iface.peers.map do |p|
          {
            "name" => p.name,
            "description" => p.description,
            "device" => p.device,
            "public_key" => p.public_key,
            "short_key" => p.short_key,
            "address" => p.clean_ips
          }
        end
        data.to_pretty_json
      end

      def self.format_peer_show(peer : Models::Peer) : String
        data = {
          "name" => peer.name,
          "description" => peer.description,
          "device" => peer.device,
          "public_key" => peer.public_key,
          "allowed_ips" => peer.allowed_ips,
          "endpoint" => peer.effective_endpoint,
          "handshake" => peer.effective_handshake,
          "latest_handshake_epoch" => peer.runtime.try(&.latest_handshake_epoch) || 0_i64,
          "rx_bytes" => peer.runtime.try(&.transfer_rx) || 0_u64,
          "tx_bytes" => peer.runtime.try(&.transfer_tx) || 0_u64,
          "rx_formatted" => peer.effective_rx,
          "tx_formatted" => peer.effective_tx,
          "online" => peer.online?
        }
        data.to_pretty_json
      end

      def self.format_interfaces(interfaces : Array(Models::Interface)) : String
        data = interfaces.map do |iface|
          {
            "name" => iface.name,
            "address" => iface.effective_address,
            "listen_port" => iface.effective_listen_port,
            "peers_count" => iface.peers.size,
            "active" => iface.active,
            "config_path" => iface.config_path
          }
        end
        data.to_pretty_json
      end

      def self.format_check(report : Config::ValidationReport) : String
        report.to_pretty_json
      end
    end
  end
end
