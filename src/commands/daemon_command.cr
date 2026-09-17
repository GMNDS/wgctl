require "../cli/context"
require "../server/daemon"
require "../server/auth/token_store"
require "../server/openapi"
require "../server/openapi_markdown"
require "../output/table"

module Wgctl
  module Commands
    class DaemonCommand
      # Resolve paths at runtime so non-root falls back to /tmp
      def self.pid_file : String
        writable?("/var/run") ? "/var/run/wgctl-daemon.pid" : "/tmp/wgctl-daemon.pid"
      end

      def self.log_file : String
        writable?("/var/log") ? "/var/log/wgctl-daemon.log" : "/tmp/wgctl-daemon.log"
      end

      private def self.writable?(dir : String) : Bool
        return false unless File.directory?(dir)
        test = File.join(dir, ".wgctl_write_test")
        File.write(test, "")
        File.delete(test)
        true
      rescue
        false
      end

      def self.run(context : CLI::Context, args : Array(String))
        subcmd = args.shift? || "start"

        case subcmd
        when "start"
          run_start(context, args)
        when "stop"
          run_stop
        when "restart"
          run_stop(quiet: true)
          sleep 1.second
          run_start(context, args)
        when "status"
          run_status
        when "token"
          run_token(context, args)
        when "docs", "openapi"
          run_docs(context, args)
        when "help", "--help", "-h"
          CLI::Help.print_daemon_help
        else
          raise "Unknown daemon subcommand '#{subcmd}'. Usage: wgctl daemon <start|stop|restart|status|token|docs>"
        end
      end

      # ─── start ───────────────────────────────────────────────────────────────

      private def self.run_start(context : CLI::Context, args : Array(String))
        port = context.port || 7443
        host = context.host
        cert_file = context.cert
        key_file = context.key
        cors_origin = context.cors
        foreground = context.foreground

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
          when "--foreground", "-f", "--daemon-foreground"
            foreground = true
          end
          i += 1
        end

        if foreground
          # Running as the background child: write our PID, then serve
          write_pid(Process.pid)
          start_server(context, port, host, cert_file, key_file, cors_origin)
        else
          {% if flag?(:unix) %}
            # Check if already running
            if (pid = read_pid) && process_alive?(pid)
              puts "wgctl daemon is already running (PID #{pid})."
              puts "Use 'wgctl daemon restart' to restart it."
              exit 1
            end

            log = log_file

            # Open (or create) the log file before spawning
            begin
              Dir.mkdir_p(File.dirname(log))
              log_fd = File.open(log, "a")
            rescue ex
              log = "/tmp/wgctl-daemon.log"
              log_fd = File.open(log, "a")
            end

            exe = Process.executable_path || "wgctl"
            bg_args = ["daemon", "start", "--daemon-foreground",
                       "--port", port.to_s, "--host", host,
                       "--cors", cors_origin]
            bg_args += ["--cert", cert_file] if cert_file
            bg_args += ["--key",  key_file]  if key_file

            child = Process.new(
              exe, bg_args,
              input: Process::Redirect::Close,
              output: log_fd,
              error: log_fd
            )
            log_fd.close

            # Give it a moment to start and write PID
            sleep 1.second

            if process_alive?(child.pid)
              puts "wgctl daemon started (PID #{child.pid})"
              puts "REST API: http://#{host}:#{port}/api/v1"
              puts "Docs:     http://#{host}:#{port}/docs"
              puts "Logs:     #{log}"
              puts ""
              puts "To stop:    wgctl daemon stop"
              puts "To restart: wgctl daemon restart"
              puts "To status:  wgctl daemon status"
            else
              puts "Failed to start daemon. Check #{log} for errors:"
              puts ""
              if File.exists?(log)
                # Print last 20 lines of log
                lines = File.read_lines(log)
                lines.last(20).each { |l| puts "  #{l}" }
              else
                puts "  (log file not found)"
              end
              exit 1
            end
          {% else %}
            puts "Background daemon mode is only supported on Linux/macOS."
            puts "Run with --foreground to start in the current terminal."
            exit 1
          {% end %}
        end
      end

      private def self.start_server(context, port, host, cert_file, key_file, cors_origin)
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

      # ─── stop ────────────────────────────────────────────────────────────────

      private def self.run_stop(quiet : Bool = false)
        pid = read_pid
        if pid.nil?
          puts "wgctl daemon is not running (no PID file found)." unless quiet
          return
        end

        {% if flag?(:unix) %}
          unless process_alive?(pid)
            puts "wgctl daemon is not running (stale PID #{pid})." unless quiet
            File.delete(pid_file) if File.exists?(pid_file)
            return
          end

          puts "Stopping wgctl daemon (PID #{pid})..." unless quiet
          Process.run("kill", ["-TERM", pid.to_s])

          # Wait up to 5s
          5.times do
            sleep 1.second
            break unless process_alive?(pid)
          end

          if process_alive?(pid)
            Process.run("kill", ["-KILL", pid.to_s])
            puts "Force-killed PID #{pid}." unless quiet
          else
            puts "wgctl daemon stopped." unless quiet
          end
        {% else %}
          Process.run("taskkill", ["/PID", pid.to_s, "/F"])
          puts "wgctl daemon stopped (PID #{pid})." unless quiet
        {% end %}

        File.delete(pid_file) if File.exists?(pid_file)
      end

      # ─── status ──────────────────────────────────────────────────────────────

      private def self.run_status
        pid = read_pid
        if pid && process_alive?(pid)
          puts "\e[32m● wgctl daemon is running\e[0m (PID #{pid})"
          puts "  Logs: #{log_file}"
        else
          puts "\e[31m● wgctl daemon is not running\e[0m"
          if File.exists?(pid_file)
            puts "  Stale PID file found (#{pid_file}) — cleaning up."
            File.delete(pid_file)
          end
        end
      end

      # ─── PID helpers ─────────────────────────────────────────────────────────

      private def self.read_pid : Int64?
        f = pid_file
        return nil unless File.exists?(f)
        File.read(f).strip.to_i64?
      rescue
        nil
      end

      private def self.write_pid(pid : Int64)
        f = pid_file
        Dir.mkdir_p(File.dirname(f))
        File.write(f, pid.to_s)
      rescue ex
        STDERR.puts "Warning: could not write PID file: #{ex.message}"
      end

      private def self.process_alive?(pid : Int64) : Bool
        Process.exists?(pid)
      rescue
        false
      end

      # ─── token ───────────────────────────────────────────────────────────────

      private def self.run_token(context : CLI::Context, args : Array(String))
        action = args.shift? || "list"
        store = Server::Auth::TokenStore.new

        case action
        when "create"
          name = context.name
          expires_arg = context.expires

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

            table.add_row([t.id, t.name, t.prefix, status, exp_str, last_used_str])
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

      # ─── docs / openapi ───────────────────────────────────────────────────────

      def self.run_docs(context : CLI::Context, args : Array(String))
        format = "markdown"
        out_file : String? = context.output_file

        i = 0
        while i < args.size
          case args[i]
          when "--format"
            i += 1
            format = args[i]?.try(&.downcase) || format
          when "--json"
            format = "json"
          when "--markdown", "--md"
            format = "markdown"
          when "-o", "--output"
            i += 1
            out_file = args[i]?
          else
            # Support: `wgctl daemon docs docs/api.md`
            if out_file.nil? && !args[i].starts_with?("-")
              out_file = args[i]
            end
          end
          i += 1
        end

        content = if format == "json"
                    Server::OpenAPISpec.generate
                  else
                    Server::OpenAPIMarkdown.generate
                  end

        if file = out_file
          dir = File.dirname(File.expand_path(file))
          Dir.mkdir_p(dir) unless Dir.exists?(dir)
          File.write(file, content)
          puts "Documentação da API gerada com sucesso em: #{file} (#{format})"
        else
          print content
        end
      end
    end
  end
end
