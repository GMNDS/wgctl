require "json"
require "./peer"

module Wgctl
  module Models
    class Interface
      include JSON::Serializable

      property name : String
      property config_path : String?
      property address : Array(String)
      property listen_port : Int32?
      
      # Never serialize private_key in status / json dump for security
      @[JSON::Field(ignore: true)]
      property private_key : String?

      # Comments or instructions before or within [Interface]
      @[JSON::Field(ignore: true)]
      property raw_headers : Array(String) = [] of String

      @[JSON::Field(ignore: true)]
      property raw_properties : Hash(String, Array(String)) = Hash(String, Array(String)).new

      property peers : Array(Peer) = [] of Peer

      # Runtime properties
      property active : Bool = false
      property runtime_public_key : String?
      property runtime_listen_port : Int32?

      def initialize(
        @name : String,
        @config_path : String? = nil,
        @address : Array(String) = [] of String,
        @listen_port : Int32? = nil,
        @private_key : String? = nil,
        @peers : Array(Peer) = [] of Peer,
        @raw_headers : Array(String) = [] of String,
        @raw_properties : Hash(String, Array(String)) = Hash(String, Array(String)).new
      )
      end

      def effective_address : String
        if @address.empty?
          "-"
        else
          @address.join(", ")
        end
      end

      def effective_listen_port : Int32?
        @listen_port || @runtime_listen_port
      end

      def find_peer(query : String) : Peer?
        @peers.find { |p| p.matches?(query) }
      end

      def peer_exists_by_name?(name : String) : Bool
        target = name.strip.downcase
        @peers.any? { |p| p.metadata.name.to_s.downcase == target }
      end

      def peer_exists_by_key?(key : String) : Bool
        target = key.strip.downcase
        @peers.any? { |p| p.public_key.downcase == target }
      end

      def peer_exists_by_ip?(target_ip : String) : Bool
        # Normalize target_ip (handle both "10.0.0.2" and "10.0.0.2/32")
        norm = target_ip.strip
        norm_clean = norm.includes?("/") ? norm.split("/").first : norm

        # Also check against interface's own addresses
        @address.each do |addr|
          clean_addr = addr.split("/").first
          return true if clean_addr == norm_clean
        end

        @peers.each do |peer|
          peer.allowed_ips.each do |ip_cidr|
            clean_peer_ip = ip_cidr.split("/").first
            return true if clean_peer_ip == norm_clean
          end
        end
        false
      end

      def all_assigned_ips : Set(String)
        set = Set(String).new
        @address.each do |addr|
          set << addr.split("/").first
        end
        @peers.each do |peer|
          peer.allowed_ips.each do |ip_cidr|
            set << ip_cidr.split("/").first
          end
        end
        set
      end
    end
  end
end
