require "./spec_helper"

describe Wgctl::Config::Parser do
  it "parses wireguard conf with metadata comments" do
    sample = <<-CONF
    # Interface level comment
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51823
    PrivateKey = serverprivkey123=

    # Server note
    # wgctl:name=asteri-c
    # wgctl:description=Contabo Germany
    # wgctl:device=server
    [Peer]
    PublicKey = asteripubkey123=
    AllowedIPs = 10.13.14.9/32

    # wgctl:name=pc
    [Peer]
    PublicKey = pcpubkey123=
    AllowedIPs = 10.13.14.2/32
    CONF

    iface = Wgctl::Config::Parser.parse_string(sample, "wg0")
    iface.name.should eq("wg0")
    iface.address.should eq(["10.13.14.1/24"])
    iface.listen_port.should eq(51823)
    iface.peers.size.should eq(2)

    p1 = iface.peers[0]
    p1.name.should eq("asteri-c")
    p1.description.should eq("Contabo Germany")
    p1.device.should eq("server")
    p1.public_key.should eq("asteripubkey123=")
    p1.allowed_ips.should eq(["10.13.14.9/32"])

    p2 = iface.peers[1]
    p2.name.should eq("pc")
    p2.public_key.should eq("pcpubkey123=")
    p2.allowed_ips.should eq(["10.13.14.2/32"])
  end
end
