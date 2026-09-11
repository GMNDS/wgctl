require "http/server"
require "json"
require "uri"
require "../cli/context"

module Wgctl
  module Server
    class WsHandler
      include HTTP::Handler

      property context : CLI::Context
      @inner_handler : HTTP::WebSocketHandler

      def initialize(@context : CLI::Context = CLI::Context.new)
        @inner_handler = HTTP::WebSocketHandler.new do |ws, http_ctx|
          path = http_ctx.request.path
          parts = path.split("/").reject(&.empty?)

          # Match: /api/v1/interfaces/:name/live
          if parts.size == 5 && parts[0] == "api" && parts[1] == "v1" && parts[2] == "interfaces" && parts[4] == "live"
            iface_name = URI.decode_www_form(parts[3])
            start_streaming(ws, iface_name)
          else
            ws.close(HTTP::WebSocket::CloseCode::NormalClosure, "Path not recognized")
          end
        end
      end

      def call(context : HTTP::Server::Context)
        upgrade = context.request.headers["Upgrade"]?.try(&.downcase)
        if upgrade == "websocket"
          @inner_handler.call(context)
        else
          call_next(context)
        end
      end

      private def start_streaming(ws : HTTP::WebSocket, iface_name : String)
        spawn do
          loop do
            break if ws.closed?

            begin
              iface = @context.load_interface(iface_name)
              peers_data = iface.peers.map do |peer|
                {
                  "name" => peer.name,
                  "public_key" => peer.public_key,
                  "online" => peer.online?,
                  "endpoint" => peer.effective_endpoint,
                  "latest_handshake" => peer.effective_handshake,
                  "transfer_rx" => peer.effective_rx,
                  "transfer_tx" => peer.effective_tx
                }
              end

              payload = {
                "event" => "metrics_update",
                "timestamp" => Time.utc,
                "interface" => iface_name,
                "peers" => peers_data
              }

              ws.send(payload.to_json)
            rescue
            end

            sleep 2.seconds
          end
        end
      end
    end
  end
end
