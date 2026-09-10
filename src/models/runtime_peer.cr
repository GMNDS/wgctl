require "json"

module Wgctl
  module Models
    class RuntimePeer
      include JSON::Serializable

      property public_key : String
      property preshared_key : String?
      property endpoint : String?
      property allowed_ips : Array(String)
      property latest_handshake_epoch : Int64
      property transfer_rx : UInt64
      property transfer_tx : UInt64
      property persistent_keepalive : Int32?

      def initialize(
        @public_key : String,
        @preshared_key : String? = nil,
        @endpoint : String? = nil,
        @allowed_ips : Array(String) = [] of String,
        @latest_handshake_epoch : Int64 = 0_i64,
        @transfer_rx : UInt64 = 0_u64,
        @transfer_tx : UInt64 = 0_u64,
        @persistent_keepalive : Int32? = nil
      )
      end

      def latest_handshake_time : Time?
        return nil if @latest_handshake_epoch <= 0
        Time.unix(@latest_handshake_epoch)
      end

      # A peer is considered online if it had a handshake within the last 3 minutes (180s)
      def online?(threshold_seconds : Int32 = 180) : Bool
        return false if @latest_handshake_epoch <= 0
        elapsed = Time.utc.to_unix - @latest_handshake_epoch
        elapsed >= 0 && elapsed <= threshold_seconds
      end

      def formatted_handshake(now : Time = Time.utc) : String
        return "offline" if @latest_handshake_epoch <= 0
        diff_seconds = now.to_unix - @latest_handshake_epoch
        return "offline" if diff_seconds < 0

        if diff_seconds < 60
          "#{diff_seconds}s ago"
        elsif diff_seconds < 3600
          "#{diff_seconds // 60}m ago"
        elsif diff_seconds < 86400
          "#{diff_seconds // 3600}h ago"
        else
          "#{diff_seconds // 86400}d ago"
        end
      end

      def formatted_rx : String
        self.class.format_bytes(@transfer_rx)
      end

      def formatted_tx : String
        self.class.format_bytes(@transfer_tx)
      end

      def self.format_bytes(bytes : UInt64) : String
        return "0 B" if bytes == 0
        units = ["B", "KB", "MB", "GB", "TB", "PB"]
        val = bytes.to_f
        unit_idx = 0
        while val >= 1024.0 && unit_idx < units.size - 1
          val /= 1024.0
          unit_idx += 1
        end

        if unit_idx == 0
          "#{bytes} B"
        elsif val >= 10.0
          "#{val.round.to_i} #{units[unit_idx]}"
        else
          rounded = (val * 10).round / 10.0
          if rounded == rounded.floor
            "#{rounded.to_i} #{units[unit_idx]}"
          else
            sprintf("%.1f %s", rounded, units[unit_idx])
          end
        end
      end
    end
  end
end
