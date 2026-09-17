require "../models/interface"

module Wgctl
  module Config
    class IPAllocator
      # Allocates the next available /32 IPv4 address from the interface's subnet
      def self.allocate_next(iface : Models::Interface) : String
        if iface.address.empty?
          raise "Interface '#{iface.name}' has no Address configured to allocate from"
        end

        # Look for the first IPv4 subnet
        ipv4_entry = iface.address.find { |a| a.includes?(".") }
        unless ipv4_entry
          raise "Interface '#{iface.name}' has no IPv4 Address configured"
        end

        # Parse "10.13.14.1/24"
        parts = ipv4_entry.split("/")
        ip_str = parts[0].strip
        prefix_len = parts.size > 1 ? parts[1].to_i? || 24 : 24

        octets = ip_str.split(".").map(&.to_u32)
        if octets.size != 4
          raise "Invalid IPv4 address format: #{ip_str}"
        end

        ip_int = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]

        mask = prefix_len == 0 ? 0_u32 : (~0_u32 << (32 - prefix_len)) & 0xFFFFFFFF_u32
        network = ip_int & mask
        broadcast = network | (~mask & 0xFFFFFFFF_u32)

        used_ips_set = iface.all_assigned_ips.to_set

        # Search candidates between (network + 1) and (broadcast - 1)
        # Skip network address and broadcast address
        start_cand = network + 1
        end_cand = broadcast > 0 ? broadcast - 1 : broadcast

        # Phase 1: Search sequentially starting immediately after interface IP up to end_cand
        first_try_start = ip_int + 1
        if first_try_start <= end_cand
          (first_try_start..end_cand).each do |cand|
            cand_str = int_to_ip(cand)
            unless used_ips_set.includes?(cand_str)
              return "#{cand_str}/32"
            end
          end
        end

        # Phase 2: Wrap around from start_cand up to ip_int - 1
        first_try_end = ip_int > 0 ? ip_int - 1 : 0_u32
        if start_cand <= first_try_end
          (start_cand..first_try_end).each do |cand|
            cand_str = int_to_ip(cand)
            unless used_ips_set.includes?(cand_str)
              return "#{cand_str}/32"
            end
          end
        end

        raise "Subnet #{ipv4_entry} has no free IP addresses available"
      end

      private def self.int_to_ip(val : UInt32) : String
        o1 = (val >> 24) & 0xFF
        o2 = (val >> 16) & 0xFF
        o3 = (val >> 8) & 0xFF
        o4 = val & 0xFF
        "#{o1}.#{o2}.#{o3}.#{o4}"
      end
    end
  end
end
