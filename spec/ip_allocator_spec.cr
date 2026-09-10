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
end
