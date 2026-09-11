require "http/server"
require "openssl"
require "./cors_handler"
require "./auth_handler"
require "./ws_handler"
require "./api_router"
require "./auth/token_store"
require "../cli/context"

module Wgctl
  module Server
    class Daemon
      property host : String
      property port : Int32
      property cert_file : String?
      property key_file : String?
      property cors_origin : String
      property context : CLI::Context
      property token_store : Auth::TokenStore
      getter server : HTTP::Server?

      def initialize(
        @context : CLI::Context = CLI::Context.new,
        @token_store : Auth::TokenStore = Auth::TokenStore.new,
        @host : String = "0.0.0.0",
        @port : Int32 = 7443,
        @cert_file : String? = nil,
        @key_file : String? = nil,
        @cors_origin : String = "*"
      )
      end

      def build_server : HTTP::Server
        cors = CORSHandler.new(@cors_origin)
        auth = AuthHandler.new(@token_store)
        ws = WsHandler.new(@context)
        router = ApiRouter.new(@context)

        handlers = [cors, auth, ws, router]
        HTTP::Server.new(handlers)
      end

      def start
        server = build_server
        @server = server

        # Register graceful shutdown signals
        Process.on_terminate do
          puts "\n[wgctl daemon] Gracefully shutting down..."
          server.close rescue nil
          exit(0)
        end

        has_tls = false
        if (cert = @cert_file) && (key = @key_file)
          if File.exists?(cert) && File.exists?(key)
            ssl_ctx = OpenSSL::SSL::Context::Server.new
            ssl_ctx.certificate_chain = cert
            ssl_ctx.private_key = key
            server.bind_tls(@host, @port, ssl_ctx)
            has_tls = true
          else
            raise "Certificate file (#{cert}) or private key (#{key}) not found."
          end
        end

        unless has_tls
          server.bind_tcp(@host, @port)
        end

        protocol = has_tls ? "https" : "http"
        ws_proto = has_tls ? "wss" : "ws"

        puts "=================================================="
        puts "  wgctl Headless REST API Daemon"
        puts "=================================================="
        puts "REST API:    #{protocol}://#{@host}:#{@port}/api/v1"
        puts "Live Stream: #{ws_proto}://#{@host}:#{@port}/api/v1/interfaces/:name/live"
        puts "Token Store: #{@token_store.path}"
        puts "CORS Origin: #{@cors_origin}"
        unless has_tls
          puts "Security:    HTTP (Plaintext). Recommendation: Use behind HTTPS reverse proxy or provide --cert and --key."
        end
        puts "=================================================="
        puts "Press Ctrl+C to stop."

        server.listen
      end

      def stop
        @server.try(&.close)
      end
    end
  end
end
