require "./spec_helper"
require "../src/server/daemon"
require "../src/server/auth/token_store"
require "../src/config/writer"
require "http/client"
require "file_utils"

describe "wgctl Headless REST API" do
  it "serves health, authenticates tokens, manages peers, and handles CORS" do
    tmp_dir = File.tempfile("api_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    token_file = File.join(tmp_dir, "tokens.json")
    server_conf_path = File.join(tmp_dir, "testwg.conf")

    # Create dummy interface configuration
    File.write(server_conf_path, <<-CONF)
    [Interface]
    PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
    Address = 10.50.0.1/24
    ListenPort = 51820
    CONF
    File.chmod(server_conf_path, 0o600)

    token_store = Wgctl::Server::Auth::TokenStore.new(token_file)
    token, raw_token = token_store.create("test-client", 1.hours)

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = server_conf_path

    cors = Wgctl::Server::CORSHandler.new("*")
    auth = Wgctl::Server::AuthHandler.new(token_store)
    router = Wgctl::Server::ApiRouter.new(ctx)

    server = HTTP::Server.new([cors, auth, router])
    port = 28443
    server.bind_tcp("127.0.0.1", port)

    spawn do
      server.listen
    end

    # Give server a moment to bind
    sleep 50.milliseconds

    begin
      # 1. Test GET /api/v1/health (unauthenticated)
      res_health = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/health")
      res_health.status_code.should eq(200)
      health_json = JSON.parse(res_health.body)
      health_json["success"].as_bool.should be_true
      health_json["data"]["status"].as_s.should eq("ok")

      # 2. Test OPTIONS (CORS preflight)
      res_options = HTTP::Client.exec("OPTIONS", "http://127.0.0.1:#{port}/api/v1/interfaces")
      res_options.status_code.should eq(204)
      res_options.headers["Access-Control-Allow-Origin"]?.should eq("*")
      res_options.headers["Access-Control-Allow-Methods"]?.not_nil!.should contain("POST")

      # 3. Test Unauthorized request without token
      res_unauth = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/interfaces")
      res_unauth.status_code.should eq(401)
      unauth_json = JSON.parse(res_unauth.body)
      unauth_json["success"].as_bool.should be_false
      unauth_json["error"]["code"].as_s.should eq("UNAUTHORIZED")

      # 4. Test Authenticated request with Bearer token
      headers = HTTP::Headers{
        "Authorization" => "Bearer #{raw_token}",
        "Content-Type"  => "application/json"
      }

      res_ifaces = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/interfaces/testwg", headers: headers)
      res_ifaces.status_code.should eq(200)
      iface_json = JSON.parse(res_ifaces.body)
      iface_json["data"]["name"].as_s.should eq("testwg")
      iface_json["data"]["address"].as_s.should eq("10.50.0.1/24")

      # 5. Test POST /api/v1/interfaces/:name/peers in Managed Mode (server generates keys)
      add_managed_payload = {
        "name"        => "managed-phone",
        "device"      => "phone",
        "description" => "Test Phone",
        "ip"          => "auto"
      }.to_json

      res_add = HTTP::Client.post("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers", headers: headers, body: add_managed_payload)
      res_add.status_code.should eq(201)
      add_json = JSON.parse(res_add.body)
      add_json["success"].as_bool.should be_true
      add_json["data"]["mode"].as_s.should eq("managed")
      add_json["data"]["name"].as_s.should eq("managed-phone")
      add_json["data"]["client_config"].as_s.should contain("[Interface]")
      add_json["data"]["allowed_ips"].as_a.first.as_s.should eq("10.50.0.2/32")
      managed_pub = add_json["data"]["public_key"].as_s

      # 6. Test POST in Zero-Knowledge Mode (client supplies public key)
      zk_pub = "ZeroKnowledgeDummyPublicKey12345678901234="
      add_zk_payload = {
        "name"       => "zk-laptop",
        "public_key" => zk_pub,
        "device"     => "laptop",
        "ip"         => "auto"
      }.to_json

      res_add_zk = HTTP::Client.post("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers", headers: headers, body: add_zk_payload)
      res_add_zk.status_code.should eq(201)
      zk_json = JSON.parse(res_add_zk.body)
      zk_json["data"]["mode"].as_s.should eq("zero_knowledge")
      zk_json["data"]["public_key"].as_s.should eq(zk_pub)
      zk_json["data"]["allowed_ips"].as_a.first.as_s.should eq("10.50.0.3/32")

      # 7. Test GET list peers
      res_peers = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers", headers: headers)
      res_peers.status_code.should eq(200)
      peers_json = JSON.parse(res_peers.body)
      peers_json["data"].as_a.size.should eq(2)

      # 8. Test PATCH edit peer
      edit_payload = {
        "description" => "Updated Phone Description"
      }.to_json
      res_edit = HTTP::Client.patch("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers/#{URI.encode_www_form(managed_pub)}", headers: headers, body: edit_payload)
      res_edit.status_code.should eq(200)
      edit_json = JSON.parse(res_edit.body)
      edit_json["data"]["description"].as_s.should eq("Updated Phone Description")

      # 9. Test GET client config
      res_conf = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers/managed-phone/config", headers: headers)
      res_conf.status_code.should eq(200)
      conf_json = JSON.parse(res_conf.body)
      conf_json["data"]["config"].as_s.should contain("10.50.0.2/32")

      # 10. Test DELETE peer
      res_del = HTTP::Client.delete("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers/managed-phone", headers: headers)
      res_del.status_code.should eq(200)

      # Check that remaining peers is 1
      res_after_del = HTTP::Client.get("http://127.0.0.1:#{port}/api/v1/interfaces/testwg/peers", headers: headers)
      JSON.parse(res_after_del.body)["data"].as_a.size.should eq(1)

    ensure
      server.close rescue nil
      FileUtils.rm_rf(tmp_dir) rescue nil
    end
  end
end
