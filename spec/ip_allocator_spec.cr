require "./spec_helper"

describe Wgctl::Config::IPAllocator do
  it "allocates the first available /32 IP address" do
    sample = <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51823

    # wgctl:name=asteri-c
    [Peer]
    PublicKey = pub1=
    AllowedIPs = 10.13.14.9/32

    # wgctl:name=pc
    [Peer]
    PublicKey = pub2=
    AllowedIPs = 10.13.14.2/32

    # wgctl:name=mobile
    [Peer]
    PublicKey = pub3=
    AllowedIPs = 10.13.14.3/32
    CONF

    iface = Wgctl::Config::Parser.parse_string(sample, "wg0")
    next_ip = Wgctl::Config::IPAllocator.allocate_next(iface)
    next_ip.should eq("10.13.14.4/32")
  end

  it "allocates quickly in large /16 subnets without excessive memory consumption" do
    sample = <<-CONF
    [Interface]
    Address = 172.16.0.1/16
    ListenPort = 51820

    [Peer]
    PublicKey = pub1=
    AllowedIPs = 172.16.0.2/32
    CONF

    iface = Wgctl::Config::Parser.parse_string(sample, "wg0")
    next_ip = Wgctl::Config::IPAllocator.allocate_next(iface)
    next_ip.should eq("172.16.0.3/32")
  end

  it "wraps around when IPs above interface are exhausted" do
    sample = <<-CONF
    [Interface]
    Address = 10.0.0.3/29
    ListenPort = 51820

    [Peer]
    PublicKey = pub1=
    AllowedIPs = 10.0.0.4/32

    [Peer]
    PublicKey = pub2=
    AllowedIPs = 10.0.0.5/32

    [Peer]
    PublicKey = pub3=
    AllowedIPs = 10.0.0.6/32
    CONF

    # /29: network is 10.0.0.0, broadcast is 10.0.0.7
    # usable: .1 to .6
    # iface is .3. .4, .5, .6 are taken.
    # free candidates above .3 are none.
    # wrap-around candidates: .1, .2
    iface = Wgctl::Config::Parser.parse_string(sample, "wg0")
    next_ip = Wgctl::Config::IPAllocator.allocate_next(iface)
    next_ip.should eq("10.0.0.1/32")
  end
end
