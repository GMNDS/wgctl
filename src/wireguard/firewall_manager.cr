module Wgctl
  module WireGuard
    class FirewallManager
      # Generates PostUp commands for wireguard configuration
      def self.generate_post_up(wan_interface : String, enable_ipv6 : Bool = false) : String
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
