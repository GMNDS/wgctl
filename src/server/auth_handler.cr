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

      def initialize(@token_store : Auth::TokenStore, @no_auth_paths : Array(String) = ["/api/v1/health"])
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
          respond_unauthorized(context, "Missing Bearer token in Authorization header or 'token' query parameter")
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
        # 1. Check Authorization: Bearer <token>
        if auth_header = request.headers["Authorization"]?
          if auth_header.starts_with?("Bearer ")
            return auth_header[7..-1].strip
          end
        end

        # 2. Check query parameter ?token=<token>
        if query = request.query
          params = URI::Params.parse(query)
          if t = params["token"]?
            return t.strip unless t.strip.empty?
          end
        end

        nil
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
