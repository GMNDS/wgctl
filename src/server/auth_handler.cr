require "http/server"
require "json"
require "uri"
require "./auth/token_store"

module Wgctl
  module Server
    class AuthHandler
      include HTTP::Handler

      property token_store : Auth::TokenStore
      property no_auth_paths : Array(String)

      def initialize(@token_store : Auth::TokenStore, @no_auth_paths : Array(String) = ["/api/v1/health", "/docs", "/docs/", "/api/v1/openapi.json"])
      end

      def call(context : HTTP::Server::Context)
        # Allow preflight CORS
        if context.request.method == "OPTIONS"
          return call_next(context)
        end

        # Allow public endpoints (health check)
        if @no_auth_paths.includes?(context.request.path)
          return call_next(context)
        end

        raw_token = extract_token(context.request)

        if raw_token.nil? || raw_token.empty?
          respond_unauthorized(context, "Missing Bearer token. Provide it via the Authorization header (WebSocket clients may use the 'token' query parameter).")
          return
        end

        authenticated_token = @token_store.authenticate(raw_token)

        if authenticated_token.nil?
          respond_unauthorized(context, "Invalid, expired, or revoked API token")
          return
        end

        call_next(context)
      end

      private def extract_token(request : HTTP::Request) : String?
        # 1. Preferred: Authorization: Bearer <token>
        if auth_header = request.headers["Authorization"]?
          if auth_header.starts_with?("Bearer ")
            return auth_header[7..-1].strip
          end
        end

        # 2. A token in the query string is ONLY tolerated for browser WebSocket
        #    upgrades on the live endpoint, because browsers cannot set custom
        #    headers during the WebSocket handshake. Everywhere else the token
        #    must travel in the Authorization header (never in URLs/logs).
        if websocket_upgrade?(request) && request.path.ends_with?("/live")
          if query = request.query
            params = URI::Params.parse(query)
            if t = params["token"]?
              return t.strip unless t.strip.empty?
            end
          end
        end

        nil
      end

      private def websocket_upgrade?(request : HTTP::Request) : Bool
        request.headers["Upgrade"]?.try(&.downcase) == "websocket"
      end

      private def respond_unauthorized(context : HTTP::Server::Context, message : String)
        context.response.status_code = 401
        context.response.headers["Content-Type"] = "application/json"
        
        err_body = {
          "success" => false,
          "error" => {
            "code" => "UNAUTHORIZED",
            "message" => message
          }
        }
        
        context.response.print(err_body.to_json)
      end
    end
  end
end
