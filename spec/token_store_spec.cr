require "./spec_helper"
require "../src/server/auth/token_store"

describe Wgctl::Server::Auth::TokenStore do
  it "creates, authenticates, expires, and revokes tokens" do
    tmp_path = File.tempfile("tokens_test", ".json").path
    File.delete(tmp_path) rescue nil

    store = Wgctl::Server::Auth::TokenStore.new(tmp_path)

    # 1. Create token with 30 days expiration
    token, raw_token = store.create("go-tui", 30.days)
    token.name.should eq("go-tui")
    token.id.should start_with("tok_")
    token.prefix.should start_with("wgctl_tok_")
    raw_token.should start_with("wgctl_tok_")
    token.expires_at.should_not be_nil

    # File should exist and contain hash, not raw token
    File.exists?(tmp_path).should be_true
    file_content = File.read(tmp_path)
    file_content.should contain(token.token_hash)
    file_content.should_not contain(raw_token)

    # 2. Authenticate with valid token
    auth_result = store.authenticate(raw_token)
    auth_result.should_not be_nil
    auth_result.not_nil!.id.should eq(token.id)
    auth_result.not_nil!.last_used_at.should_not be_nil

    # 3. Authenticate with invalid token
    store.authenticate("wgctl_tok_invalid12345").should be_nil

    # 4. Test expired token
    expired_token, expired_raw = store.create("expired-app", -1.hours)
    expired_token.expired?.should be_true
    store.authenticate(expired_raw).should be_nil

    # 5. Revoke token
    revoked = store.revoke(token.id)
    revoked.should be_true
    store.authenticate(raw_token).should be_nil

    # 6. Reload store from disk
    reloaded_store = Wgctl::Server::Auth::TokenStore.new(tmp_path)
    reloaded_store.list.size.should eq(2)
    reloaded_store.list.find { |t| t.id == token.id }.not_nil!.revoked?.should be_true

    File.delete(tmp_path) rescue nil
  end

  it "automatically registers and authenticates tokens from WGCTL_TOKEN" do
    tmp_path = File.tempfile("env_tok_test", ".json").path
    File.delete(tmp_path) rescue nil

    ENV["WGCTL_TOKEN"] = "wgctl_tok_secret_from_env_123456"
    begin
      store = Wgctl::Server::Auth::TokenStore.new(tmp_path)
      token = store.authenticate("wgctl_tok_secret_from_env_123456")
      token.should_not be_nil
      token.not_nil!.name.should eq("env-secret")
    ensure
      ENV.delete("WGCTL_TOKEN")
      File.delete(tmp_path) rescue nil
    end
  end

  it "automatically registers and authenticates tokens from WGCTL_TOKEN_FILE" do
    tmp_path = File.tempfile("file_tok_test", ".json").path
    File.delete(tmp_path) rescue nil

    secret_file = File.tempfile("docker_secret", ".txt").path
    File.write(secret_file, "wgctl_tok_docker_secret_789012\n")

    ENV["WGCTL_TOKEN_FILE"] = secret_file
    begin
      store = Wgctl::Server::Auth::TokenStore.new(tmp_path)
      token = store.authenticate("wgctl_tok_docker_secret_789012")
      token.should_not be_nil
      token.not_nil!.name.should eq("env-secret")
    ensure
      ENV.delete("WGCTL_TOKEN_FILE")
      File.delete(secret_file) rescue nil
      File.delete(tmp_path) rescue nil
    end
  end
end
