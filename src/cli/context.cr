require "../models/interface"
require "../config/parser"
require "../wireguard/runner"
require "../wireguard/dump_parser"

module Wgctl
  module CLI
    class Context
      property config_file : String?
      property json_output : Bool = false
      property dry_run : Bool = false
      property qr_code : Bool = false
      def qr=(v : Bool); @qr_code = v; end
      def qr : Bool; @qr_code; end
      property output_file : String?
      property ip : String?
      property description : String?
      property device : String?
      property name : String?
      property keepalive : Int32?
      property preshared_key : String?
      property endpoint : String?
      property no_apply : Bool = false
      property wan_interface : String?
      property public_ip : String?
      property port : Int32?
      property subnet : String?
      property dns : String?
      property first_client : String?
      property non_interactive : Bool = false
      property no_firewall : Bool = false
      property no_start : Bool = false
      property host : String = "0.0.0.0"
      property cert : String?
      property key : String?
      property cors : String = "*"
      property expires : String?

      def initialize
      end

      # Finds all available WireGuard configuration files and active interfaces
      def available_configs : Hash(String, String)
        configs = Hash(String, String).new # iface_name -> path

        # 1. Check /etc/wireguard/*.conf
        if Dir.exists?("/etc/wireguard")
          Dir.glob("/etc/wireguard/*.conf").each do |file|
            iface_name = File.basename(file, ".conf")
            configs[iface_name] = file
          end
        end

        # 2. Check current working directory for *.conf (helps dev/testing)
        Dir.glob("./*.conf").each do |file|
          iface_name = File.basename(file, ".conf")
          configs[iface_name] ||= File.expand_path(file)
        end

        configs
      end

      # Returns sorted list of all unique interface names available (configured or active)
      def discover_interfaces : Array(String)
        configs = available_configs
        active_ifaces = WireGuard::Runner.list_active_interfaces rescue [] of String
        (configs.keys + active_ifaces).uniq.sort
      end

      # Discovers or resolves the target interface configuration
      def resolve_interface(target_name : String? = nil) : Tuple(String, String)
        # Explicit config file supplied via --config
        if cfg = @config_file
          unless File.exists?(cfg)
            raise "Config file not found: #{cfg}"
          end
          iface_name = target_name || File.basename(cfg, ".conf")
          return {iface_name, File.expand_path(cfg)}
        end

        configs = available_configs

        # Explicit interface name provided as argument (e.g. wg0)
        if target = target_name
          if path = configs[target]?
            return {target, path}
          end

          # Direct fallback to standard path
          std_path = "/etc/wireguard/#{target}.conf"
          if File.exists?(std_path)
            return {target, std_path}
          end

          # Check if interface is active even without .conf
          active_ifaces = WireGuard::Runner.list_active_interfaces
          if active_ifaces.includes?(target)
            return {target, std_path}
          end

          raise "Interface '#{target}' not found in /etc/wireguard/ or current directory."
        end

        # No target given: auto-discovery
        if configs.size == 1
          iface_name = configs.keys.first
          return {iface_name, configs[iface_name]}
        elsif configs.size > 1
          names = configs.keys.sort.join(", ")
          raise "Multiple WireGuard configurations found (#{names}). Please specify an interface (e.g. wgctl status #{configs.keys.first})"
        end

        # If no config files found, check active live interfaces
        active_ifaces = WireGuard::Runner.list_active_interfaces
        if active_ifaces.size == 1
          target = active_ifaces.first
          return {target, "/etc/wireguard/#{target}.conf"}
        elsif active_ifaces.size > 1
          names = active_ifaces.join(", ")
          raise "Multiple active interfaces found (#{names}). Please specify one."
        end

        raise "No WireGuard interfaces or configuration files found in /etc/wireguard/ or current directory."
      end

      # Loads interface with both parsed config and live runtime dump
      def load_interface(target_name : String? = nil) : Models::Interface
        iface_name, path = resolve_interface(target_name)

        if File.exists?(path)
          iface = Config::Parser.parse_file(path, iface_name)
        else
          iface = Models::Interface.new(name: iface_name, config_path: path)
        end

        # Enrich with live runtime dump if available
        if dump = WireGuard::Runner.fetch_dump(iface_name)
          WireGuard::DumpParser.parse(dump, iface)
        end

        iface
      end
    end
  end
end
