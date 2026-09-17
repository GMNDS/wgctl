require "./spec_helper"
require "../src/server/auth/token_store"

describe "Security and Parser Hardening Audit" do
  describe "CRLF / INI Injection Defense" do
    it "sanitizes newline characters in Metadata#to_comments" do
      meta = Wgctl::Models::Metadata.new(
        name: "malicious\n[Interface]\nPostUp=evil_command",
        description: "harmless\r\n[Peer]\nPublicKey=injected",
        device: "phone\nattack",
        client_private_key: "priv\nkey"
      )

      comments = meta.to_comments
      comments.each do |line|
        line.should_not contain("\n")
        line.should_not contain("\r")
        line.should start_with("# wgctl:")
      end

      comments.should contain("# wgctl:name=malicious[Interface]PostUp=evil_command")
      comments.should contain("# wgctl:description=harmless[Peer]PublicKey=injected")
    end

    it "rejects peer metadata containing newlines in Validator" do
      iface = Wgctl::Models::Interface.new(name: "wg0")
      iface.address << "10.13.14.1/24"
      iface.private_key = "test_priv_key"

      peer = Wgctl::Models::Peer.new(
        public_key: "test_pub_key_1234567890=",
        metadata: Wgctl::Models::Metadata.new(name: "peer\nevil"),
        allowed_ips: ["10.13.14.2/32"]
      )
      iface.peers << peer

      report = Wgctl::Config::Validator.validate(iface)
      report.valid?.should be_false
      report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Error && i.message.includes?("newline") }.should be_true
    end

    it "rejects peer description or device containing newlines in Validator" do
      iface = Wgctl::Models::Interface.new(name: "wg0")
      iface.address << "10.13.14.1/24"
      iface.private_key = "test_priv_key"

      peer = Wgctl::Models::Peer.new(
        public_key: "test_pub_key_1234567890=",
        metadata: Wgctl::Models::Metadata.new(name: "safe-peer", description: "bad\ndescription"),
        allowed_ips: ["10.13.14.2/32"]
      )
      iface.peers << peer

      report = Wgctl::Config::Validator.validate(iface)
      report.valid?.should be_false
      report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Error && i.message.includes?("description contains invalid newline") }.should be_true
    end

    it "rejects invalid characters in peer name as a validation error" do
      iface = Wgctl::Models::Interface.new(name: "wg0")
      iface.address << "10.13.14.1/24"
      iface.private_key = "test_priv_key"

      peer = Wgctl::Models::Peer.new(
        public_key: "test_pub_key_1234567890=",
        metadata: Wgctl::Models::Metadata.new(name: "peer with spaces;"),
        allowed_ips: ["10.13.14.2/32"]
      )
      iface.peers << peer

      report = Wgctl::Config::Validator.validate(iface)
      report.valid?.should be_false
      report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Error && i.message.includes?("contains invalid characters") }.should be_true
    end
  end

  describe "Path Traversal & Interface Name Validation" do
    it "rejects path traversal sequences in interface name" do
      ctx = Wgctl::CLI::Context.new

      expect_raises(Exception, /Invalid interface name/) do
        ctx.resolve_interface("../../etc/shadow")
      end

      expect_raises(Exception, /Invalid interface name/) do
        ctx.resolve_interface("wg0/test")
      end

      expect_raises(Exception, /Invalid interface name/) do
        ctx.resolve_interface("wg0;rm -rf")
      end

      expect_raises(Exception, /Invalid interface name/) do
        ctx.resolve_interface("verylonginterfacenamethatexceeds15chars")
      end
    end

    it "validates interface name in Validator" do
      iface = Wgctl::Models::Interface.new(name: "../../etc/shadow")
      iface.address << "10.13.14.1/24"
      iface.private_key = "test_priv_key"

      report = Wgctl::Config::Validator.validate(iface)
      report.valid?.should be_false
      report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Error && i.message.includes?("invalid interface name") }.should be_true
    end
  end

  describe "Authentication Timing Attack Resistance" do
    it "authenticates valid tokens with constant-time comparison" do
      tmp_store_file = File.tempfile("token_test", ".json")
      begin
        store = Wgctl::Server::Auth::TokenStore.new(tmp_store_file.path)
        token, raw = store.create("ci-token")

        authenticated = store.authenticate(raw)
        authenticated.should_not be_nil
        authenticated.not_nil!.id.should eq(token.id)

        # Invalid token
        store.authenticate("wgctl_tok_invalid123456").should be_nil
      ensure
        tmp_store_file.delete rescue nil
      end
    end
  end

  describe "IP Allocator Robustness" do
    it "handles malformed IP entries defensively without crash" do
      iface = Wgctl::Models::Interface.new(name: "wg0")
      iface.address << "invalid.ip.format.here/24"

      expect_raises(Exception, /Invalid IPv4 address format/) do
        Wgctl::Config::IPAllocator.allocate_next(iface)
      end

      iface.address.clear
      iface.address << "999.999.999.999/24"

      expect_raises(Exception, /Invalid IPv4 address format/) do
        Wgctl::Config::IPAllocator.allocate_next(iface)
      end
    end
  end
end
