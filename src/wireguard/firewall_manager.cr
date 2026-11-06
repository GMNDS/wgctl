module Wgctl
  module WireGuard
    class FirewallManager
      # Linux interface names are limited to 15 characters (IFNAMSIZ - 1) and a
      # restricted charset. This also blocks shell metacharacters, which matters
      # because wg-quick runs PostUp/PostDown through a shell as root.
      WAN_INTERFACE_PATTERN = /\A[a-zA-Z0-9_.:@-]{1,15}\z/

      def self.valid_interface_name?(name : String) : Bool
        !!(name =~ WAN_INTERFACE_PATTERN)
      end

      private def self.validate_wan_interface!(wan_interface : String)
        return if valid_interface_name?(wan_interface)
        raise "Invalid WAN interface name '#{wan_interface}'. Allowed: letters, digits, '.', '_', '-', ':', '@', up to 15 characters."
      end

      # Generates PostUp commands for wireguard configuration
      def self.generate_post_up(wan_interface : String, enable_ipv6 : Bool = false) : String
        validate_wan_interface!(wan_interface)
        cmds = [] of String
        cmds << "iptables -A FORWARD -i %i -j ACCEPT"
        cmds << "iptables -A FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT"
        cmds << "iptables -t nat -A POSTROUTING -o #{wan_interface} -j MASQUERADE"

        if enable_ipv6
          cmds << "ip6tables -A FORWARD -i %i -j ACCEPT"
          cmds << "ip6tables -A FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT"
          cmds << "ip6tables -t nat -A POSTROUTING -o #{wan_interface} -j MASQUERADE"
        end

        cmds.join("; ")
      end

      # Generates PostDown commands for wireguard configuration
      def self.generate_post_down(wan_interface : String, enable_ipv6 : Bool = false) : String
        validate_wan_interface!(wan_interface)
        cmds = [] of String
        cmds << "iptables -D FORWARD -i %i -j ACCEPT"
        cmds << "iptables -D FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT"
        cmds << "iptables -t nat -D POSTROUTING -o #{wan_interface} -j MASQUERADE"

        if enable_ipv6
          cmds << "ip6tables -D FORWARD -i %i -j ACCEPT"
          cmds << "ip6tables -D FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT"
          cmds << "ip6tables -t nat -D POSTROUTING -o #{wan_interface} -j MASQUERADE"
        end

        cmds.join("; ")
      end
    end
  end
end
