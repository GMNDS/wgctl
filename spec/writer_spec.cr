require "./spec_helper"

describe Wgctl::Config::Writer do
  it "formats interface and peers preserving metadata comments" do
    iface = Wgctl::Models::Interface.new(
      name: "wg0",
      address: ["10.13.14.1/24"],
      listen_port: 51823,
      private_key: "my_priv_key="
    )

    meta = Wgctl::Models::Metadata.new(
      name: "asteri-c",
      description: "Contabo Germany",
      device: "server"
    )

    peer = Wgctl::Models::Peer.new(
      public_key: "my_pub_key=",
      allowed_ips: ["10.13.14.9/32"],
      metadata: meta
    )
    iface.peers << peer

    output = Wgctl::Config::Writer.format(iface)

    output.should contain("[Interface]")
    output.should contain("Address = 10.13.14.1/24")
    output.should contain("ListenPort = 51823")
    output.should contain("# wgctl:name=asteri-c")
    output.should contain("# wgctl:description=Contabo Germany")
    output.should contain("# wgctl:device=server")
    output.should contain("[Peer]")
    output.should contain("PublicKey = my_pub_key=")
    output.should contain("AllowedIPs = 10.13.14.9/32")
  end
end
