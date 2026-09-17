require "http/client"
require "json"
require "uri"
require "../models/interface"
require "../models/peer"
require "../models/metadata"
require "../models/runtime_peer"

module Wgctl
  module Client
    class ApiClient
      property base_url : String
      property token : String

      def initialize(@base_url : String, @token : String)
        # Normalize URL: strip trailing slashes
        @base_url = @base_url.rstrip("/")
      end

      # ─── Health & Connectivity ──────────────────────────────────────────────

      def health : JSON::Any
        response = get("/api/v1/health", auth: false)
        extract_data(response)
      end

      # ─── Interfaces ─────────────────────────────────────────────────────────

      def list_interfaces : Array(String)
        response = get("/api/v1/interfaces")
        data = extract_data(response)
        data.as_a.map(&.as_s)
      end

      def get_interface(name : String) : Models::Interface
        response = get("/api/v1/interfaces/#{URI.encode_www_form(name)}")
        data = extract_data(response)

        peers = list_peers(name)

        address_val = data["address"]?.try(&.as_s?)
        addresses = address_val && !address_val.empty? ? [address_val] : [] of String
        port_val = data["listen_port"]?.try(&.as_i?)

        iface = Models::Interface.new(
          name: data["name"].as_s,
          config_path: data["config_path"]?.try(&.as_s?),
          address: addresses,
          listen_port: port_val,
          peers: peers
        )

        iface.active = data["active"]?.try(&.as_bool) || false
        iface.runtime_public_key = data["public_key"]?.try(&.as_s?)
        iface.runtime_listen_port = port_val

        iface
      end

      def check_interface(name : String) : JSON::Any
        response = get("/api/v1/interfaces/#{URI.encode_www_form(name)}/check")
        extract_data(response)
      end

      def apply_interface(name : String) : String
        response = post("/api/v1/interfaces/#{URI.encode_www_form(name)}/apply")
        data = extract_data(response)
        data["message"]?.try(&.as_s) || "Applied successfully"
      end

      # ─── Peers ──────────────────────────────────────────────────────────────

      def list_peers(iface_name : String) : Array(Models::Peer)
        response = get("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers")
        data = extract_data(response)

        data.as_a.map do |item|
          parse_peer(item)
        end
      end

      def get_peer(iface_name : String, key_or_name : String) : Models::Peer
        response = get("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers/#{URI.encode_www_form(key_or_name)}")
        data = extract_data(response)
        parse_peer(data)
      end

      def add_peer(iface_name : String, payload : Hash(String, String | Int32 | Nil)) : JSON::Any
        response = post("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers", body: payload.to_json)
        extract_data(response)
      end

      def edit_peer(iface_name : String, key_or_name : String, payload : Hash(String, String | Int32 | Nil)) : Models::Peer
        response = patch("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers/#{URI.encode_www_form(key_or_name)}", body: payload.to_json)
        data = extract_data(response)
        parse_peer(data)
      end

      def delete_peer(iface_name : String, key_or_name : String) : String
        response = delete("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers/#{URI.encode_www_form(key_or_name)}")
        data = extract_data(response)
        data["message"]?.try(&.as_s) || "Peer removed"
      end

      def get_client_config(iface_name : String, key_or_name : String) : String
        response = get("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers/#{URI.encode_www_form(key_or_name)}/config", headers: HTTP::Headers{"Accept" => "text/plain"})
        if response.status_code == 200
          response.body
        else
          # Handle JSON error
          extract_data(response)
          ""
        end
      end

      def get_peer_qr(iface_name : String, key_or_name : String) : Tuple(String, String?)
        response = get("/api/v1/interfaces/#{URI.encode_www_form(iface_name)}/peers/#{URI.encode_www_form(key_or_name)}/qr")
        data = extract_data(response)
        config = data["config"].as_s
        qr_text = data["qr_text"]?.try(&.as_s?)
        {config, qr_text}
      end

      # ─── HTTP Helpers ───────────────────────────────────────────────────────

      private def get(path : String, auth : Bool = true, headers : HTTP::Headers? = nil) : HTTP::Client::Response
        req_headers = default_headers(auth)
        if headers
          headers.each { |k, v| req_headers[k] = v }
        end
        execute_request("GET", path, headers: req_headers)
      end

      private def post(path : String, body : String? = nil, auth : Bool = true) : HTTP::Client::Response
        execute_request("POST", path, body: body, headers: default_headers(auth))
      end

      private def patch(path : String, body : String? = nil, auth : Bool = true) : HTTP::Client::Response
        execute_request("PATCH", path, body: body, headers: default_headers(auth))
      end

      private def delete(path : String, auth : Bool = true) : HTTP::Client::Response
        execute_request("DELETE", path, headers: default_headers(auth))
      end

      private def default_headers(auth : Bool) : HTTP::Headers
        headers = HTTP::Headers{
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
        if auth
          headers["Authorization"] = "Bearer #{@token}"
        end
        headers
      end

      private def execute_request(method : String, path : String, body : String? = nil, headers : HTTP::Headers? = nil) : HTTP::Client::Response
        uri = URI.parse("#{@base_url}#{path}")
        client = HTTP::Client.new(uri)
        client.connect_timeout = 5.seconds
        client.read_timeout = 15.seconds

        # Configure TLS if HTTPS
        if uri.scheme == "https"
          client.tls?
        end

        begin
          client.exec(method, uri.request_target, headers: headers, body: body)
        ensure
          client.close rescue nil
        end
      rescue ex
        raise "Remote connection error (#{base_url}): #{ex.message}"
      end

      private def extract_data(response : HTTP::Client::Response) : JSON::Any
        parsed = JSON.parse(response.body) rescue nil
        if parsed.nil?
          raise "Invalid response from remote server (HTTP #{response.status_code}): #{response.body}"
        end

        if response.status_code >= 200 && response.status_code < 300
          if parsed["success"]?.try(&.as_bool)
            parsed["data"]
          else
            parsed
          end
        else
          err_msg = parsed.dig?("error", "message").try(&.as_s?) || "HTTP #{response.status_code}: #{response.body}"
          raise err_msg
        end
      end

      private def parse_peer(item : JSON::Any) : Models::Peer
        name = item["name"]?.try(&.as_s)
        desc = item["description"]?.try(&.as_s)
        dev = item["device"]?.try(&.as_s)

        metadata = Models::Metadata.new(
          name: name,
          description: desc,
          device: dev
        )

        allowed_ips = item["allowed_ips"]?.try(&.as_a.map(&.as_s)) || [] of String
        pub_key = item["public_key"]?.try(&.as_s) || ""

        rx = item["transfer_rx"]?.try(&.as_i64?.try(&.to_u64)) || 0_u64
        tx = item["transfer_tx"]?.try(&.as_i64?.try(&.to_u64)) || 0_u64
        endpoint = item["endpoint"]?.try(&.as_s?)
        
        handshake_epoch = 0_i64
        if hs_str = item["latest_handshake"]?.try(&.as_s?)
          begin
            handshake_epoch = Time.parse_iso8601(hs_str).to_unix
          rescue
            handshake_epoch = 0_i64
          end
        end

        runtime = Models::RuntimePeer.new(
          public_key: pub_key,
          endpoint: endpoint,
          allowed_ips: allowed_ips,
          latest_handshake_epoch: handshake_epoch,
          transfer_rx: rx,
          transfer_tx: tx
        )

        Models::Peer.new(
          public_key: pub_key,
          allowed_ips: allowed_ips,
          metadata: metadata,
          endpoint: endpoint,
          runtime: runtime
        )
      end
    end
  end
end
