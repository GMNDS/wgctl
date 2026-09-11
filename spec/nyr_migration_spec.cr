require "./spec_helper"
require "file_utils"

describe "Nyr wireguard-install compatibility & migration" do
  it "recognizes # BEGIN_PEER comments from Nyr's script automatically" do
    nyr_conf = <<-CONF
    # Do not alter the commented lines
    # They are used by wireguard-install
    # ENDPOINT 203.0.113.1

    [Interface]
    Address = 10.13.14.1/24
    PrivateKey = aServerPrivateKeyBase64ForTesting123456789012=
    ListenPort = 51820

    # BEGIN_PEER phone
    [Peer]
    PublicKey = pubKeyForPhone123456789012345678901234567=
    PresharedKey = pskForPhone12345678901234567890123456789012=
    AllowedIPs = 10.13.14.2/32
    # END_PEER phone

    # BEGIN_PEER laptop
    [Peer]
    PublicKey = pubKeyForLaptop12345678901234567890123456=
    AllowedIPs = 10.13.14.3/32
    # END_PEER laptop
    CONF

    iface = Wgctl::Config::Parser.parse_string(nyr_conf, "wg0")
    iface.peers.size.should eq(2)

    # Nyr peer names should be recognized automatically
    iface.peers[0].name.should eq("phone")
    iface.peers[0].allowed_ips.should eq(["10.13.14.2/32"])

    iface.peers[1].name.should eq("laptop")
    iface.peers[1].allowed_ips.should eq(["10.13.14.3/32"])

    # Server endpoint should be recognized automatically
    iface.endpoint.should eq("203.0.113.1")
  end

  it "migrates Nyr comments to # wgctl:* format" do
    tmp_file = File.tempfile("nyr_test", ".conf").path
    File.write(tmp_file, <<-CONF
    # ENDPOINT 203.0.113.1
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = wBE64BHskDhVYR8fZSatxJaLKzGj4n9O8yxFNoN2u0c=

    # BEGIN_PEER phone
    [Peer]
    PublicKey = pubKeyForPhone123456789012345678901234567=
    AllowedIPs = 10.13.14.2/32
    # END_PEER phone
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = tmp_file

    Wgctl::Commands::MigrateCommand.run(ctx, [] of String)

    saved_content = File.read(tmp_file)
    saved_content.should contain("# wgctl:name=phone")
    saved_content.should_not contain("# BEGIN_PEER")
    saved_content.should_not contain("# END_PEER")

    File.delete(tmp_file) rescue nil
  end
end
