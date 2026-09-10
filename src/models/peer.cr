require "json"
require "./metadata"
require "./runtime_peer"

module Wgctl
  module Models
    class Peer
      include JSON::Serializable

      property metadata : Metadata
      property public_key : String
      property preshared_key : String?
      property allowed_ips : Array(String)
      property endpoint : String?
      property persistent_keepalive : Int32?

      # Non-wgctl comments above this peer
      @[JSON::Field(ignore: true)]
      property raw_comments : Array(String) = [] of String

      # Custom or unmanaged properties inside [Peer]
      @[JSON::Field(ignore: true)]
      property raw_properties : Hash(String, String) = Hash(String, String).new

      # Runtime state populated from `wg show <iface> dump`
      property runtime : RuntimePeer?

      def initialize(
        @public_key : String,
        @allowed_ips : Array(String) = [] of String,
        @metadata : Metadata = Metadata.new,
        @preshared_key : String? = nil,
        @endpoint : String? = nil,
        @persistent_keepalive : Int32? = nil,
        @raw_comments : Array(String) = [] of String,
        @raw_properties : Hash(String, String) = Hash(String, String).new,
        @runtime : RuntimePeer? = nil
      )
      end

      def name : String
        n = @metadata.name
        if n && !n.strip.empty?
          n.strip
        else
          short_key
        end
      end

      def short_key : String
        if @public_key.size >= 10
          "#{@public_key[0...4]}...#{@public_key[-3..-1]}"
        elsif @public_key.size >= 8
          "#{@public_key[0...8]}..."
        else
          @public_key
        end
      end

      def has_name? : Bool
        n = @metadata.name
        !n.nil? && !n.strip.empty?
      end

      def description : String?
        @metadata.description
      end

      def device : String?
        @metadata.device
      end

      def online? : Bool
        @runtime.try(&.online?) || false
      end

      def status_label : String
        online? ? "online" : "offline"
      end

      def effective_endpoint : String
        rt_ep = @runtime.try(&.endpoint)
        if rt_ep && rt_ep != "(none)" && !rt_ep.empty?
          rt_ep
        elsif @endpoint && !@endpoint.to_s.empty?
          @endpoint.to_s
        else
          "-"
        end
      end

      def effective_handshake : String
        @runtime.try(&.formatted_handshake) || "offline"
      end

      def effective_rx : String
        @runtime.try(&.formatted_rx) || "0 B"
      end

      def effective_tx : String
        @runtime.try(&.formatted_tx) || "0 B"
      end

      def primary_ip : String
        if @allowed_ips.empty?
          "-"
        else
          ip = @allowed_ips.first
          ip.ends_with?("/32") ? ip[0...-3] : ip
        end
      end

      def clean_ips : String
        @allowed_ips.join(", ")
      end

      # Matches a query by name or public key (full or prefix)
      def matches?(query : String) : Bool
        q = query.strip.downcase
        return true if @metadata.name.to_s.downcase == q
        return true if @public_key.downcase == q
        return true if @public_key.downcase.starts_with?(q)
        false
      end
    end
  end
end
