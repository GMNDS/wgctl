require "./spec_helper"
require "../src/config/allowed_ips"
require "../src/models/interface"
require "../src/models/peer"

describe Wgctl::Config::AllowedIPs do
  describe ".vpn_subnet" do
    it "calculates /24 network from interface address" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      Wgctl::Config::AllowedIPs.vpn_subnet(iface).should eq("10.13.14.0/24")
    end

    it "calculates /16 network from interface address" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["172.16.5.10/16"])
      Wgctl::Config::AllowedIPs.vpn_subnet(iface).should eq("172.16.0.0/16")
    end

    it "calculates /8 network from interface address" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.5.2.1/8"])
      Wgctl::Config::AllowedIPs.vpn_subnet(iface).should eq("10.0.0.0/8")
    end

    it "handles address without prefix length defaulting to /24" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1"])
      Wgctl::Config::AllowedIPs.vpn_subnet(iface).should eq("10.13.14.0/24")
    end
  end

  describe ".normalize" do
    it "normalizes 'all', 'full', 'internet' to 0.0.0.0/0, ::/0" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      Wgctl::Config::AllowedIPs.normalize("all", iface).should eq("0.0.0.0/0, ::/0")
      Wgctl::Config::AllowedIPs.normalize("full", iface).should eq("0.0.0.0/0, ::/0")
      Wgctl::Config::AllowedIPs.normalize("internet", iface).should eq("0.0.0.0/0, ::/0")
    end

    it "normalizes 'vpn', 'split', 'subnet' to calculated interface subnet" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      Wgctl::Config::AllowedIPs.normalize("vpn", iface).should eq("10.13.14.0/24")
      Wgctl::Config::AllowedIPs.normalize("split", iface).should eq("10.13.14.0/24")
      Wgctl::Config::AllowedIPs.normalize("subnet", iface).should eq("10.13.14.0/24")
    end

    it "normalizes custom CIDRs list" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      Wgctl::Config::AllowedIPs.normalize("10.13.14.0/24, 192.168.1.0/24", iface).should eq("10.13.14.0/24, 192.168.1.0/24")
      Wgctl::Config::AllowedIPs.normalize("10.0.0.0/8", iface).should eq("10.0.0.0/8")
    end
  end

  describe ".resolve" do
    it "defaults to full tunnel when nothing is specified" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      Wgctl::Config::AllowedIPs.resolve(iface).should eq("0.0.0.0/0, ::/0")
    end

    it "uses peer metadata when explicit is nil" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      peer = Wgctl::Models::Peer.new(
        public_key: "pubkey",
        metadata: Wgctl::Models::Metadata.new(client_allowed_ips: "vpn")
      )
      Wgctl::Config::AllowedIPs.resolve(iface, peer).should eq("10.13.14.0/24")
    end

    it "explicit setting overrides peer metadata" do
      iface = Wgctl::Models::Interface.new(name: "wg0", address: ["10.13.14.1/24"])
      peer = Wgctl::Models::Peer.new(
        public_key: "pubkey",
        metadata: Wgctl::Models::Metadata.new(client_allowed_ips: "vpn")
      )
      Wgctl::Config::AllowedIPs.resolve(iface, peer, explicit: "all").should eq("0.0.0.0/0, ::/0")
    end
  end
end
