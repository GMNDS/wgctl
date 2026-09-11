require "../cli/context"
require "../server/daemon"
require "../server/auth/token_store"
require "../output/table"

module Wgctl
  module Commands
    class DaemonCommand
      def self.run(context : CLI::Context, args : Array(String))
        subcmd = args.shift? || "start"

        case subcmd
        when "start"
          run_start(context, args)
        when "token"
          run_token(context, args)
        when "help", "--help", "-h"
          print_help
        else
          raise "Unknown daemon subcommand '#{subcmd}'. Usage: wgctl daemon <start|token> [options]"
        end
      end

      private def self.run_start(context : CLI::Context, args : Array(String))
        port = context.port || 7443
        host = context.host
        cert_file = context.cert
        key_file = context.key
        cors_origin = context.cors

        # Parse inline flags if any
        i = 0
        while i < args.size
          arg = args[i]
          case arg
          when "--port", "-p"
            i += 1
            port = args[i]?.try(&.to_i?) || port
          when "--host", "-H"
            i += 1
            host = args[i]? || host
          when "--cert"
            i += 1
            cert_file = args[i]?
          when "--key"
            i += 1
            key_file = args[i]?
          when "--cors"
            i += 1
            cors_origin = args[i]? || cors_origin
          end
          i += 1
        end

        token_store = Server::Auth::TokenStore.new
        daemon = Server::Daemon.new(
          context: context,
          token_store: token_store,
          host: host,
          port: port,
          cert_file: cert_file,
          key_file: key_file,
          cors_origin: cors_origin
        )

        daemon.start
      end

      private def self.run_token(context : CLI::Context, args : Array(String))
        action = args.shift? || "list"
        store = Server::Auth::TokenStore.new

        case action
        when "create"
          name = context.name
          expires_arg = context.expires

          # Parse optional inline args
          i = 0
          while i < args.size
            arg = args[i]
            case arg
            when "--name", "-n"
              i += 1
              name = args[i]?
            when "--expires", "-e"
              i += 1
              expires_arg = args[i]?
            else
              name ||= arg
            end
            i += 1
          end

          if name.nil? || name.strip.empty?
            raise "Missing token name. Usage: wgctl daemon token create --name <name> [--expires 30d]"
          end

          duration : Time::Span? = parse_duration(expires_arg || "30d")
          token, raw_secret = store.create(name.strip, duration)

          puts "=================================================="
          puts "  New API Token Created"
          puts "=================================================="
          puts "Name:       #{token.name}"
          puts "ID:         #{token.id}"
          puts "Expires:    #{token.expires_at ? token.expires_at.not_nil!.to_s("%Y-%m-%d %H:%M:%S UTC") : "Never"}"
          puts "Token:      \e[1;32m#{raw_secret}\e[0m"
          puts "=================================================="
          puts "IMPORTANT: Copy and save this token now."
          puts "You will NOT be able to retrieve it again from the server."
          puts "\nUse in HTTP requests:"
          puts "  Authorization: Bearer #{raw_secret}"
          puts "Use in WebSockets:"
          puts "  ws://host:7443/api/v1/interfaces/wg0/live?token=#{raw_secret}"

        when "list"
          tokens = store.list
          if tokens.empty?
            puts "No API tokens found. Create one with: wgctl daemon token create --name <name>"
            return
          end

          table = Output::Table.new(["ID", "NAME", "PREFIX", "STATUS", "EXPIRES AT", "LAST USED"])
          now = Time.utc

          tokens.each do |t|
            status = if t.revoked?
                       "\e[31mREVOKED\e[0m"
                     elsif t.expired?(now)
                       "\e[33mEXPIRED\e[0m"
                     else
                       "\e[32mACTIVE\e[0m"
                     end

            exp_str = t.expires_at ? t.expires_at.not_nil!.to_s("%Y-%m-%d %H:%M") : "Never"
            last_used_str = t.last_used_at ? t.last_used_at.not_nil!.to_s("%Y-%m-%d %H:%M") : "Never"

            table.add_row([
              t.id,
              t.name,
              t.prefix,
              status,
              exp_str,
              last_used_str
            ])
          end

          puts table.render

        when "revoke"
          target = args.first? || context.name
          if target.nil? || target.strip.empty?
            raise "Missing token ID or name. Usage: wgctl daemon token revoke <id|name>"
          end

          if store.revoke(target.strip)
            puts "Token '#{target}' has been successfully revoked."
          else
            raise "Token '#{target}' not found or already revoked."
          end

        else
          raise "Unknown token action '#{action}'. Usage: wgctl daemon token <create|list|revoke>"
        end
      end

      private def self.parse_duration(str : String) : Time::Span?
        clean = str.strip.downcase
        return nil if clean == "never" || clean == "0" || clean == "infinite"

        if clean =~ /^(\d+)d$/
          $1.to_i.days
        elsif clean =~ /^(\d+)h$/
          $1.to_i.hours
        elsif clean =~ /^(\d+)m$/
          $1.to_i.minutes
        elsif clean =~ /^(\d+)y$/
          ($1.to_i * 365).days
        else
          30.days
        end
      end

      private def self.print_help
        puts <<-HELP
        wgctl daemon - Headless REST API and background server

        Usage:
          wgctl daemon start [options]
          wgctl daemon token create --name <name> [--expires 30d]
          wgctl daemon token list
          wgctl daemon token revoke <id|name>

        Start Options:
          --port, -p PORT         Port to bind (default: 7443)
          --host, -H HOST         Host IP to bind (default: 0.0.0.0)
          --cert CERT_FILE        Path to SSL/TLS certificate chain (for HTTPS)
          --key KEY_FILE          Path to SSL/TLS private key
          --cors ORIGIN           Allowed CORS origin (default: "*")

        Token Options:
          --name, -n NAME         Descriptive name for the API token
          --expires, -e DURATION  Expiration time (e.g. 7d, 30d, 90d, 1y, never)
        HELP
      end
    end
  end
end
