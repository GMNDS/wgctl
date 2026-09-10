require "../models/interface"
require "../models/peer"
require "../config/validator"
require "./table"

module Wgctl
  module Output
    class Formatter
      def self.format_status(iface : Models::Interface) : String
        io = IO::Memory.new
        io.puts "Interface: #{iface.name}"
        io.puts "Address: #{iface.effective_address}"
        if port = iface.effective_listen_port
          io.puts "Listen Port: #{port}"
        end
        io.puts ""

        table = Table.new(["NAME", "IP", "ENDPOINT", "HANDSHAKE", "RX", "TX"])

        iface.peers.each do |peer|
          table.add_row([
            peer.name,
            peer.primary_ip,
            peer.effective_endpoint,
            peer.effective_handshake,
            peer.effective_rx,
            peer.effective_tx
          ])
        end

        io.print table.render
        io.to_s
      end

      def self.format_peers(iface : Models::Interface) : String
        table = Table.new(["NAME", "ADDRESS", "PUBLIC KEY"])

        iface.peers.each do |peer|
          table.add_row([
            peer.name,
            peer.primary_ip,
            peer.short_key
          ])
        end

        table.render
      end

      def self.format_peer_show(peer : Models::Peer) : String
        io = IO::Memory.new
        io.puts sprintf("%-14s%s", "Name:", peer.name)
        if desc = peer.description
          io.puts sprintf("%-14s%s", "Description:", desc)
        end
        if dev = peer.device
          io.puts sprintf("%-14s%s", "Device:", dev)
        end
        io.puts sprintf("%-14s%s", "Public Key:", peer.public_key)
        io.puts sprintf("%-14s%s", "Allowed IPs:", peer.clean_ips)
        io.puts sprintf("%-14s%s", "Endpoint:", peer.effective_endpoint)
        io.puts sprintf("%-14s%s", "Handshake:", peer.effective_handshake)
        io.puts sprintf("%-14s%s", "Received:", peer.effective_rx)
        io.puts sprintf("%-14s%s", "Sent:", peer.effective_tx)
        io.to_s
      end

      def self.format_interfaces(interfaces : Array(Models::Interface)) : String
        table = Table.new(["INTERFACE", "ADDRESS", "PORT", "PEERS", "STATUS"])

        interfaces.each do |iface|
          status_str = iface.active ? "active" : "down"
          table.add_row([
            iface.name,
            iface.effective_address,
            iface.effective_listen_port.try(&.to_s) || "-",
            iface.peers.size.to_s,
            status_str
          ])
        end

        table.render
      end

      def self.format_check(report : Config::ValidationReport) : String
        io = IO::Memory.new
        io.puts "✓ interface #{report.interface_name}"
        io.puts "✓ #{report.peer_count} peers"

        errs = report.issues.select { |i| i.severity == Config::Severity::Error }
        warns = report.issues.select { |i| i.severity == Config::Severity::Warning }

        has_duplicate_ips = errs.any? { |e| e.message.includes?("assigned to multiple peers") }
        unless has_duplicate_ips
          io.puts "✓ no duplicate addresses"
        end

        io.puts "" if warns.size > 0 || errs.size > 0

        warns.each do |w|
          io.puts "WARN #{w.message}"
        end

        errs.each do |e|
          io.puts "ERROR #{e.message}"
        end

        io.to_s
      end
    end
  end
end
