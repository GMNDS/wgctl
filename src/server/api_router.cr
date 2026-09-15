require "http/server"
require "json"
require "uri"
require "../cli/context"
require "../models/interface"
require "../models/peer"
require "../models/metadata"
require "../config/writer"
require "../config/validator"
require "../config/ip_allocator"
require "../wireguard/keys"
require "../wireguard/runner"
require "../commands/version_command"
require "./openapi"

module Wgctl
  module Server
    class ApiRouter
      include HTTP::Handler

      property context : CLI::Context

      def initialize(@context : CLI::Context = CLI::Context.new)
      end

      def call(context : HTTP::Server::Context)
        path = context.request.path
        method = context.request.method

        # Ensure JSON response by default
        context.response.headers["Content-Type"] = "application/json"

        begin
          route(context, method, path)
        rescue ex : Exception
          respond_error(context, 500, "INTERNAL_ERROR", ex.message || "An unexpected error occurred")
        end
      end

      private def route(context : HTTP::Server::Context, method : String, path : String)
        parts = path.split("/").reject(&.empty?)

        # /api/v1/...
        if parts.size >= 2 && parts[0] == "api" && parts[1] == "v1"
          subparts = parts[2..-1]

          # GET /api/v1/health
          if subparts == ["health"] && method == "GET"
            return handle_health(context)
          end

          # GET /api/v1/interfaces
          if subparts == ["interfaces"] && method == "GET"
            return handle_list_interfaces(context)
          end

          # /api/v1/interfaces/:name...
          if subparts.size >= 2 && subparts[0] == "interfaces"
            iface_name = URI.decode_www_form(subparts[1])

            # GET /api/v1/interfaces/:name
            if subparts.size == 2 && method == "GET"
              return handle_get_interface(context, iface_name)
            end

            # POST /api/v1/interfaces/:name/apply
            if subparts.size == 3 && subparts[2] == "apply" && method == "POST"
              return handle_apply_interface(context, iface_name)
            end

            # GET /api/v1/interfaces/:name/check
            if subparts.size == 3 && subparts[2] == "check" && method == "GET"
              return handle_check_interface(context, iface_name)
            end

            # /api/v1/interfaces/:name/peers...
            if subparts.size >= 3 && subparts[2] == "peers"
              # GET /api/v1/interfaces/:name/peers
              if subparts.size == 3 && method == "GET"
                return handle_list_peers(context, iface_name)
              end

              # POST /api/v1/interfaces/:name/peers
              if subparts.size == 3 && method == "POST"
                return handle_add_peer(context, iface_name)
              end

              if subparts.size >= 4
                peer_key = URI.decode_www_form(subparts[3])

                # GET /api/v1/interfaces/:name/peers/:key
                if subparts.size == 4 && method == "GET"
                  return handle_get_peer(context, iface_name, peer_key)
                end

                # PATCH /api/v1/interfaces/:name/peers/:key
                if subparts.size == 4 && (method == "PATCH" || method == "PUT")
                  return handle_edit_peer(context, iface_name, peer_key)
                end

                # DELETE /api/v1/interfaces/:name/peers/:key
                if subparts.size == 4 && method == "DELETE"
                  return handle_delete_peer(context, iface_name, peer_key)
                end

                # GET /api/v1/interfaces/:name/peers/:key/config
                if subparts.size == 5 && subparts[4] == "config" && method == "GET"
                  return handle_get_client_config(context, iface_name, peer_key)
                end

                # GET /api/v1/interfaces/:name/peers/:key/qr
                if subparts.size == 5 && subparts[4] == "qr" && method == "GET"
                  return handle_get_peer_qr(context, iface_name, peer_key)
                end
              end
            end
          end
        end

        # GET /docs  →  Swagger UI
        if (path == "/docs" || path == "/docs/") && method == "GET"
          context.response.headers["Content-Type"] = "text/html; charset=utf-8"
          context.response.print(OpenAPISpec::SWAGGER_UI_HTML)
          return
        end

        # GET /api/v1/openapi.json  →  OpenAPI 3.0 spec
        if subparts == ["openapi.json"] && method == "GET"
          scheme = context.request.headers["X-Forwarded-Proto"]? || "http"
          host_header = context.request.headers["Host"]? || "localhost"
          context.response.headers["Content-Type"] = "application/json"
          context.response.print(OpenAPISpec.generate(host_header, scheme: scheme))
          return
        end

        respond_error(context, 404, "NOT_FOUND", "Endpoint not found: #{method} #{path}")
      end

      # --- Handlers ---

      private def handle_health(context : HTTP::Server::Context)
        respond_json(context, 200, {
          "status" => "ok",
          "version" => Commands::VersionCommand::VERSION,
          "timestamp" => Time.utc
        })
      end

      private def handle_list_interfaces(context : HTTP::Server::Context)
        discovered = @context.discover_interfaces
        respond_json(context, 200, discovered)
      end

      private def handle_get_interface(context : HTTP::Server::Context, iface_name : String)
        iface = load_iface(context, iface_name) || return

        data = {
          "name" => iface.name,
          "address" => iface.effective_address,
          "listen_port" => iface.effective_listen_port,
          "public_key" => iface.runtime_public_key,
          "active" => iface.active,
          "peer_count" => iface.peers.size,
          "online_peer_count" => iface.peers.count(&.online?),
          "config_path" => iface.config_path
        }

        respond_json(context, 200, data)
      end

      private def handle_list_peers(context : HTTP::Server::Context, iface_name : String)
        iface = load_iface(context, iface_name) || return

        peers_data = iface.peers.map do |peer|
          serialize_peer(peer)
        end

        respond_json(context, 200, peers_data)
      end

      private def handle_get_peer(context : HTTP::Server::Context, iface_name : String, peer_key : String)
        iface = load_iface(context, iface_name) || return
        peer = iface.find_peer(peer_key)

        unless peer
          respond_error(context, 404, "PEER_NOT_FOUND", "Peer '#{peer_key}' not found in #{iface_name}")
          return
        end

        respond_json(context, 200, serialize_peer(peer))
      end

      private def handle_add_peer(context : HTTP::Server::Context, iface_name : String)
        iface = load_iface(context, iface_name) || return
        body = parse_json_body(context) || return

        name = body["name"]?.try(&.as_s.strip)
        if name.nil? || name.empty?
          respond_error(context, 400, "MISSING_NAME", "Field 'name' is required.")
          return
        end

        if iface.peer_exists_by_name?(name)
          respond_error(context, 409, "NAME_EXISTS", "A peer with name '#{name}' already exists.")
          return
        end

        # Mode determination: Zero-Knowledge if public_key provided, Managed if generated
        provided_pub = body["public_key"]?.try(&.as_s.strip)
        client_priv_key : String? = nil
        client_pub_key : String

        if provided_pub && !provided_pub.empty?
          client_pub_key = provided_pub
          is_zero_knowledge = true
        else
          client_priv_key = WireGuard::Keys.generate_private_key
          client_pub_key = WireGuard::Keys.public_key(client_priv_key)
          is_zero_knowledge = false
        end

        # IP determination
        requested_ip = body["ip"]?.try(&.as_s.strip) || "auto"
        if requested_ip.downcase == "auto"
          allocated_ip = Config::IPAllocator.allocate_next(iface)
        else
          allocated_ip = requested_ip.includes?("/") ? requested_ip : "#{requested_ip}/32"
          if iface.peer_exists_by_ip?(allocated_ip)
            respond_error(context, 409, "IP_EXISTS", "IP address #{allocated_ip} is already assigned.")
            return
          end
        end

        device = body["device"]?.try(&.as_s.strip) || "device"
        description = body["description"]?.try(&.as_s.strip)
        keepalive = body["keepalive"]?.try(&.as_i) || 25

        metadata = Models::Metadata.new(
          name: name,
          description: description,
          device: device,
          client_private_key: client_priv_key
        )

        new_peer = Models::Peer.new(
          public_key: client_pub_key,
          allowed_ips: [allocated_ip],
          persistent_keepalive: keepalive,
          metadata: metadata
        )

        iface.peers << new_peer

        # Validate
        report = Config::Validator.validate(iface)
        unless report.valid?
          iface.peers.pop
          errs = report.issues.map(&.message).join("; ")
          respond_error(context, 400, "VALIDATION_FAILED", errs)
          return
        end

        # Save config
        config_path = iface.config_path || "/etc/wireguard/#{iface.name}.conf"
        Config::Writer.save_atomically(iface, config_path, create_backup: true)

        # Sync live
        if iface.active
          WireGuard::Runner.apply_syncconf(iface.name, config_path)
        end

        # Build response client config
        client_conf_str = generate_client_conf(iface, new_peer)
        qr_text = WireGuard::Runner.generate_qr_terminal(client_conf_str) rescue nil

        response_payload = {
          "name" => new_peer.name,
          "public_key" => new_peer.public_key,
          "allowed_ips" => new_peer.allowed_ips,
          "mode" => (is_zero_knowledge ? "zero_knowledge" : "managed"),
          "client_config" => client_conf_str,
          "qr_text" => qr_text
        }

        respond_json(context, 201, response_payload)
      end

      private def handle_edit_peer(context : HTTP::Server::Context, iface_name : String, peer_key : String)
        iface = load_iface(context, iface_name) || return
        peer = iface.find_peer(peer_key)
        unless peer
          respond_error(context, 404, "PEER_NOT_FOUND", "Peer '#{peer_key}' not found in #{iface_name}")
          return
        end

        body = parse_json_body(context) || return

        if new_name = body["name"]?.try(&.as_s.strip)
          if !new_name.empty? && new_name != peer.name
            if iface.peer_exists_by_name?(new_name)
              respond_error(context, 409, "NAME_EXISTS", "Peer name '#{new_name}' already exists.")
              return
            end
            peer.metadata.name = new_name
          end
        end

        if desc = body["description"]?.try(&.as_s.strip)
          peer.metadata.description = desc
        end

        if dev = body["device"]?.try(&.as_s.strip)
          peer.metadata.device = dev
        end

        if ip_arg = body["ip"]?.try(&.as_s.strip)
          unless ip_arg.empty?
            target_ip = ip_arg.downcase == "auto" ? Config::IPAllocator.allocate_next(iface) : (ip_arg.includes?("/") ? ip_arg : "#{ip_arg}/32")
            if target_ip != peer.primary_ip && iface.peer_exists_by_ip?(target_ip)
              respond_error(context, 409, "IP_EXISTS", "IP #{target_ip} is already assigned.")
              return
            end
            peer.allowed_ips = [target_ip]
          end
        end

        if ka = body["keepalive"]?.try(&.as_i)
          peer.persistent_keepalive = ka
        end

        # Validate
        report = Config::Validator.validate(iface)
        unless report.valid?
          errs = report.issues.map(&.message).join("; ")
          respond_error(context, 400, "VALIDATION_FAILED", errs)
          return
        end

        # Save and sync
        config_path = iface.config_path || "/etc/wireguard/#{iface.name}.conf"
        Config::Writer.save_atomically(iface, config_path, create_backup: true)
        if iface.active
          WireGuard::Runner.apply_syncconf(iface.name, config_path)
        end

        respond_json(context, 200, serialize_peer(peer))
      end

      private def handle_delete_peer(context : HTTP::Server::Context, iface_name : String, peer_key : String)
        iface = load_iface(context, iface_name) || return
        peer = iface.find_peer(peer_key)
        unless peer
          respond_error(context, 404, "PEER_NOT_FOUND", "Peer '#{peer_key}' not found in #{iface_name}")
          return
        end

        iface.peers.reject! { |p| p.public_key == peer.public_key }

        config_path = iface.config_path || "/etc/wireguard/#{iface.name}.conf"
        Config::Writer.save_atomically(iface, config_path, create_backup: true)
        if iface.active
          WireGuard::Runner.apply_syncconf(iface.name, config_path)
        end

        respond_json(context, 200, {
          "message" => "Peer '#{peer.name}' successfully removed from #{iface.name}"
        })
      end

      private def handle_get_client_config(context : HTTP::Server::Context, iface_name : String, peer_key : String)
        iface = load_iface(context, iface_name) || return
        peer = iface.find_peer(peer_key)
        unless peer
          respond_error(context, 404, "PEER_NOT_FOUND", "Peer '#{peer_key}' not found in #{iface_name}")
          return
        end

        client_conf = generate_client_conf(iface, peer)

        if context.request.headers["Accept"]? == "text/plain"
          context.response.headers["Content-Type"] = "text/plain; charset=utf-8"
          context.response.print(client_conf)
        else
          respond_json(context, 200, {
            "name" => peer.name,
            "filename" => "#{peer.name}.conf",
            "config" => client_conf
          })
        end
      end

      private def handle_get_peer_qr(context : HTTP::Server::Context, iface_name : String, peer_key : String)
        iface = load_iface(context, iface_name) || return
        peer = iface.find_peer(peer_key)
        unless peer
          respond_error(context, 404, "PEER_NOT_FOUND", "Peer '#{peer_key}' not found in #{iface_name}")
          return
        end

        client_conf = generate_client_conf(iface, peer)
        qr_text = WireGuard::Runner.generate_qr_terminal(client_conf) rescue nil

        respond_json(context, 200, {
          "name" => peer.name,
          "config" => client_conf,
          "qr_text" => qr_text
        })
      end

      private def handle_apply_interface(context : HTTP::Server::Context, iface_name : String)
        iface = load_iface(context, iface_name) || return
        config_path = iface.config_path || "/etc/wireguard/#{iface.name}.conf"

        applied, msg = WireGuard::Runner.apply_syncconf(iface.name, config_path)
        if applied
          respond_json(context, 200, {"applied" => true, "message" => msg})
        else
          respond_error(context, 500, "SYNC_FAILED", msg)
        end
      end

      private def handle_check_interface(context : HTTP::Server::Context, iface_name : String)
        iface = load_iface(context, iface_name) || return
        report = Config::Validator.validate(iface)

        issues_data = report.issues.map do |iss|
          {
            "severity" => iss.severity.to_s.downcase,
            "message" => iss.message
          }
        end

        respond_json(context, 200, {
          "valid" => report.valid?,
          "issues" => issues_data
        })
      end

      # --- Helper Methods ---

      private def load_iface(context : HTTP::Server::Context, name : String) : Models::Interface?
        begin
          @context.load_interface(name)
        rescue ex
          respond_error(context, 404, "INTERFACE_NOT_FOUND", "Interface '#{name}' could not be loaded: #{ex.message}")
          nil
        end
      end

      private def parse_json_body(context : HTTP::Server::Context) : JSON::Any?
        body_str = context.request.body.try(&.gets_to_end) || ""
        if body_str.empty?
          respond_error(context, 400, "INVALID_BODY", "Request body cannot be empty.")
          return nil
        end

        JSON.parse(body_str) rescue begin
          respond_error(context, 400, "MALFORMED_JSON", "Invalid JSON payload.")
          nil
        end
      end

      private def serialize_peer(peer : Models::Peer)
        {
          "name" => peer.name,
          "has_name" => peer.has_name?,
          "public_key" => peer.public_key,
          "allowed_ips" => peer.allowed_ips,
          "primary_ip" => peer.primary_ip,
          "description" => peer.description || "",
          "device" => peer.device || "",
          "online" => peer.online?,
          "endpoint" => peer.effective_endpoint,
          "latest_handshake" => peer.effective_handshake,
          "transfer_rx" => peer.effective_rx,
          "transfer_tx" => peer.effective_tx
        }
      end

      private def generate_client_conf(iface : Models::Interface, peer : Models::Peer) : String
        client_priv = peer.metadata.client_private_key || "<REPLACE_WITH_CLIENT_PRIVATE_KEY>"
        server_pub = iface.runtime_public_key
        if (server_pub.nil? || server_pub.empty?) && iface.private_key
          server_pub = WireGuard::Keys.public_key(iface.private_key.not_nil!) rescue nil
        end
        server_pub ||= "<SERVER_PUBLIC_KEY>"

        server_port = iface.effective_listen_port || 51820
        endpoint = detect_endpoint(iface, server_port)
        allowed_ips = calculate_client_allowed_ips(iface)

        io = IO::Memory.new
        io.puts "[Interface]"
        io.puts "PrivateKey = #{client_priv}"
        io.puts "Address = #{peer.clean_ips}"
        if dns = iface.raw_properties["DNS"]?.try(&.join(", "))
          io.puts "DNS = #{dns}"
        end
        io.puts ""
        io.puts "[Peer]"
        io.puts "PublicKey = #{server_pub}"
        io.puts "Endpoint = #{endpoint}"
        io.puts "AllowedIPs = #{allowed_ips}"
        io.puts "PersistentKeepalive = #{peer.persistent_keepalive || 25}"
        io.to_s
      end

      private def detect_endpoint(iface : Models::Interface, port : Int32) : String
        if custom_ep = iface.endpoint
          return custom_ep.includes?(":") ? custom_ep : "#{custom_ep}:#{port}"
        end
        host = System.hostname rescue "vpn.example.com"
        "#{host}:#{port}"
      end

      private def calculate_client_allowed_ips(iface : Models::Interface) : String
        ipv4 = iface.address.find { |a| a.includes?(".") }
        return "0.0.0.0/0, ::/0" unless ipv4
        parts = ipv4.split("/")
        ip_str = parts[0]
        segments = ip_str.split(".")
        if segments.size == 4
          "#{segments[0]}.#{segments[1]}.#{segments[2]}.0/24"
        else
          "0.0.0.0/0, ::/0"
        end
      end

      private def respond_json(context : HTTP::Server::Context, status_code : Int32, data : Object)
        context.response.status_code = status_code
        payload = {
          "success" => true,
          "data" => data
        }
        context.response.print(payload.to_json)
      end

      private def respond_error(context : HTTP::Server::Context, status_code : Int32, code : String, message : String)
        context.response.status_code = status_code
        payload = {
          "success" => false,
          "error" => {
            "code" => code,
            "message" => message
          }
        }
        context.response.print(payload.to_json)
      end
    end
  end
end
