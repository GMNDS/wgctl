require "./spec_helper"
require "http/server"
require "file_utils"
require "../src/client/config"
require "../src/client/api_client"
require "../src/commands/remote_command"

describe "Remote Client & Config" do
  tmp_dir = File.tempfile("remote_spec_test", "").path
  File.delete(tmp_dir) rescue nil
  Dir.mkdir_p(tmp_dir)

  ENV["WGCTL_CONFIG_DIR"] = tmp_dir

  after_all do
    FileUtils.rm_rf(tmp_dir)
  end

  it "saves, loads and manages remote profiles" do
    config = Wgctl::Client::Config.load
    config.profiles.empty?.should be_true

    prof = Wgctl::Client::RemoteProfile.new(
      url: "https://vpn.example.com:7443",
      token: "wgctl_tok_test123",
      default_interface: "wg0"
    )

    config.add_profile("production", prof, set_active: true)
    config.active_profile.should eq("production")

    loaded = Wgctl::Client::Config.load
    loaded.profiles.size.should eq(1)
    loaded.profiles["production"].url.should eq("https://vpn.example.com:7443")
    loaded.current_profile.not_nil!.token.should eq("wgctl_tok_test123")

    loaded.remove_profile("production").should be_true
    loaded.profiles.empty?.should be_true
  end

  it "communicates with mock REST server via ApiClient" do
    server = HTTP::Server.new do |context|
      path = context.request.path
      auth = context.request.headers["Authorization"]?

      context.response.headers["Content-Type"] = "application/json"

      if path == "/api/v1/health"
        context.response.print({
          "success" => true,
          "data" => {
            "status" => "ok",
            "version" => "0.5.0",
            "timestamp" => Time.utc
          }
        }.to_json)
      elsif path == "/api/v1/interfaces"
        if auth == "Bearer valid_token"
          context.response.print({
            "success" => true,
            "data" => ["wg0", "wg1"]
          }.to_json)
        else
          context.response.status_code = 401
          context.response.print({
            "success" => false,
            "error" => {"code" => "UNAUTHORIZED", "message" => "Invalid token"}
          }.to_json)
        end
      else
        context.response.status_code = 404
        context.response.print({"success" => false}.to_json)
      end
    end

    port = 28991
    spawn do
      server.bind_tcp("127.0.0.1", port)
      server.listen
    end

    # Give server time to bind
    sleep 0.1.seconds

    client = Wgctl::Client::ApiClient.new("http://127.0.0.1:#{port}", "valid_token")
    health = client.health
    health["status"].as_s.should eq("ok")
    health["version"].as_s.should eq("0.5.0")

    ifaces = client.list_interfaces
    ifaces.should eq(["wg0", "wg1"])

    # Invalid token test
    bad_client = Wgctl::Client::ApiClient.new("http://127.0.0.1:#{port}", "wrong_token")
    expect_raises(Exception, "Invalid token") do
      bad_client.list_interfaces
    end

    server.close
  end
end
