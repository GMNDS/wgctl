require "../cli/context"
require "../client/config"
require "../client/api_client"
require "../output/table"

module Wgctl
  module Commands
    class RemoteCommand
      def self.run(context : CLI::Context, args : Array(String))
        action = args.shift? || "status"

        case action
        when "connect", "attach", "add"
          run_connect(context, args)
        when "list", "ls"
          run_list
        when "use", "switch"
          run_use(args.first?)
        when "status"
          run_status(context)
        when "disconnect", "clear", "remove", "rm"
          run_disconnect(args.first?)
        when "help", "--help", "-h"
          CLI::Help.print_remote_help
        else
          raise "Unknown remote action '#{action}'. Usage: wgctl remote <connect|list|use|status|disconnect>"
        end
      end

      # ─── connect ─────────────────────────────────────────────────────────────

      private def self.run_connect(context : CLI::Context, args : Array(String))
        url : String? = nil
        token : String? = context.remote_token
        name : String? = context.remote_profile_name
        default_iface : String? = context.interface

        i = 0
        while i < args.size
          arg = args[i]
          case arg
          when "--token", "-t"
            i += 1
            token = args[i]?
          when "--name", "-n"
            i += 1
            name = args[i]?
          when "--interface", "-i"
            i += 1
            default_iface = args[i]?
          else
            if url.nil? && (arg.starts_with?("http://") || arg.starts_with?("https://") || arg.includes?(":"))
              url = arg
            elsif token.nil? && arg.starts_with?("wgctl_")
              token = arg
            end
          end
          i += 1
        end

        url ||= context.remote_url

        if url.nil? || url.strip.empty?
          raise "Missing remote server URL. Usage: wgctl remote connect <url> --token <token> [--name <name>]"
        end

        # Ensure scheme
        unless url.starts_with?("http://") || url.starts_with?("https://")
          url = "https://#{url}"
        end

        if token.nil? || token.strip.empty?
          raise "Missing API Bearer token. Usage: wgctl remote connect <url> --token <token>"
        end

        clean_url = url.strip.rstrip("/")
        clean_token = token.strip
        profile_name = (name || URI.parse(clean_url).host || "remote").strip

        puts "Connecting to #{clean_url}..."
        client = Client::ApiClient.new(clean_url, clean_token)

        # Validate connection
        health = client.health rescue nil
        if health.nil?
          # Try list_interfaces as fallback
          begin
            ifaces = client.list_interfaces
          rescue ex
            raise "Failed to connect to remote server #{clean_url}: #{ex.message}"
          end
        else
          server_version = health["version"]?.try(&.as_s?) || "unknown"
          puts "✓ Server reachable (wgctl v#{server_version})"
        end

        ifaces = client.list_interfaces
        default_iface ||= ifaces.first?

        # Save profile
        profile = Client::RemoteProfile.new(
          url: clean_url,
          token: clean_token,
          default_interface: default_iface
        )

        config = Client::Config.load
        config.add_profile(profile_name, profile, set_active: true)

        puts "✓ Connected and saved profile '#{profile_name}'"
        puts "Default interface: #{default_iface || "none"}"
        puts ""
        puts "You can now run commands remotely:"
        puts "  wgctl status"
        puts "  wgctl peers"
        puts "  wgctl peer add <nome> --ip auto"
        puts "  wgctl menu"
      end

      # ─── list ────────────────────────────────────────────────────────────────

      private def self.run_list
        config = Client::Config.load
        if config.profiles.empty?
          puts "No remote servers configured."
          puts "Connect to a server with: wgctl remote connect <url> --token <token>"
          return
        end

        table = Output::Table.new(["ACTIVE", "PROFILE", "SERVER URL", "DEFAULT IFACE"])
        config.profiles.each do |name, prof|
          active_mark = (config.active_profile == name) ? "\e[32m● (active)\e[0m" : ""
          table.add_row([
            active_mark,
            name,
            prof.url,
            prof.default_interface || "-"
          ])
        end

        puts table.render
      end

      # ─── use ─────────────────────────────────────────────────────────────────

      private def self.run_use(name : String?)
        if name.nil? || name.strip.empty?
          raise "Missing profile name. Usage: wgctl remote use <profile-name>"
        end

        config = Client::Config.load
        clean_name = name.strip
        unless config.profiles.has_key?(clean_name)
          available = config.profiles.keys.join(", ")
          raise "Remote profile '#{clean_name}' not found. Available: #{available}"
        end

        config.active_profile = clean_name
        config.save
        prof = config.profiles[clean_name]
        puts "Switched active remote server to '#{clean_name}' (#{prof.url})"
      end

      # ─── status ──────────────────────────────────────────────────────────────

      private def self.run_status(context : CLI::Context)
        config = Client::Config.load
        active_name = config.active_profile
        profile = config.current_profile

        if profile.nil?
          puts "No active remote connection."
          puts "Operating in: \e[1mLocal Mode\e[0m"
          puts "To connect to a remote server: wgctl remote connect <url> --token <token>"
          return
        end

        puts "=================================================="
        puts "  wgctl Remote Client Status"
        puts "=================================================="
        puts "Profile:   \e[1;32m#{active_name}\e[0m"
        puts "Server:    #{profile.url}"
        puts "Interface: #{profile.default_interface || "auto"}"

        # Ping health
        client = Client::ApiClient.new(profile.url, profile.token)
        start_time = Time.instant
        begin
          health = client.health
          latency_ms = (Time.instant - start_time).total_milliseconds.round(1)
          version = health["version"]?.try(&.as_s?) || "unknown"
          puts "Latency:   #{latency_ms} ms"
          puts "Remote v:  v#{version}"
          puts "Status:    \e[32mCONNECTED\e[0m"
        rescue ex
          puts "Status:    \e[31mUNREACHABLE (#{ex.message})\e[0m"
        end
        puts "=================================================="
        puts ""
        puts "Run 'wgctl remote disconnect' to return to local mode."
      end

      # ─── disconnect ──────────────────────────────────────────────────────────

      private def self.run_disconnect(name : String?)
        config = Client::Config.load

        if name
          if config.remove_profile(name)
            puts "Removed remote profile '#{name}'."
          else
            raise "Remote profile '#{name}' not found."
          end
        else
          if config.active_profile
            old = config.active_profile
            config.active_profile = nil
            config.save
            puts "Disconnected from remote server '#{old}'. Returned to \e[1mLocal Mode\e[0m."
          else
            puts "Already in Local Mode (no active remote connection)."
          end
        end
      end
    end
  end
end
