require "./spec_helper"

describe Wgctl::WireGuard::DumpParser do
  it "parses wg show dump output and formats handshake and transfer" do
    sample_conf = <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51823

    # wgctl:name=asteri-c
    [Peer]
    PublicKey = pubAsteri123=
    AllowedIPs = 10.13.14.9/32
    CONF

    iface = Wgctl::Config::Parser.parse_string(sample_conf, "wg0")

    now = Time.utc
    handshake_12s = now.to_unix - 12

    dump_output = "serverpriv\tserverpub\t51823\toff\n" +
                  "pubAsteri123=\t(none)\t1.2.3.4:32910\t10.13.14.9/32\t#{handshake_12s}\t86000000\t32500000\toff\n"

    Wgctl::WireGuard::DumpParser.parse(dump_output, iface)

    peer = iface.peers.first
    peer.runtime.should_not be_nil
    rp = peer.runtime.not_nil!

    rp.online?.should be_true
    rp.formatted_handshake(now).should eq("12s ago")
    rp.formatted_rx.should eq("82 MB")
    rp.formatted_tx.should eq("31 MB")
    peer.effective_endpoint.should eq("1.2.3.4:32910")
  end
end
