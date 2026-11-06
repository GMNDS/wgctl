require "./ip_allocator"
require "../models/interface"
require "../models/peer"

module Wgctl
  module Config
    class AllowedIPs
      FULL_TUNNEL = "0.0.0.0/0, ::/0"

      # Calculates the VPN subnet for an interface (e.g. 10.13.14.0/24)
      def self.vpn_subnet(iface : Models::Interface) : String
        IPAllocator.calculate_vpn_subnet(iface)
      end

      # Resolves client AllowedIPs from:
      # 1. explicit requested setting (CLI --allowed-ips or API query param)
      # 2. peer metadata (peer.metadata.client_allowed_ips)
      # 3. default (FULL_TUNNEL: "0.0.0.0/0, ::/0")
      def self.resolve(iface : Models::Interface, peer : Models::Peer? = nil, explicit : String? = nil) : String
        candidate = explicit
        if candidate.nil? || candidate.strip.empty?
          candidate = peer.try(&.metadata.client_allowed_ips)
        end

        if candidate.nil? || candidate.strip.empty?
          return FULL_TUNNEL
        end

        normalize(candidate, iface)
      end

      # Normalizes preset values or validates custom CIDRs:
      # - "all", "full", "internet" -> FULL_TUNNEL ("0.0.0.0/0, ::/0")
      # - "vpn", "split", "subnet" -> calculates interface subnet (e.g. "10.13.14.0/24")
      # - custom CIDRs list (e.g. "10.13.14.0/24, 192.168.10.0/24") -> normalized comma list
      def self.normalize(input : String, iface : Models::Interface) : String
        trimmed = input.strip
        case trimmed.downcase
        when "all", "full", "internet"
          FULL_TUNNEL
        when "vpn", "split", "subnet"
          vpn_subnet(iface)
        else
          # Custom list of CIDRs
          trimmed.split(",").map(&.strip).reject(&.empty?).join(", ")
        end
      end
    end
  end
end
