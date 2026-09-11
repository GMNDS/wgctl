require "./spec_helper"
require "file_utils"

class MultiInterfaceMockContext < Wgctl::CLI::Context
  property mock_configs : Hash(String, String) = Hash(String, String).new

  def available_configs : Hash(String, String)
    @mock_configs
  end
end

describe "wgctl peer show with multiple interfaces" do
  it "works automatically when only one interface exists" do
    tmp_dir = File.tempfile("single_iface_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    conf_path = File.join(tmp_dir, "wg0.conf")
    File.write(conf_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = aaaaaaaa=

    # wgctl:name=myphone
    [Peer]
    PublicKey = bbbbbbbb=
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = MultiInterfaceMockContext.new
    ctx.mock_configs = {"wg0" => conf_path}

    # Should not raise
    Wgctl::Commands::PeerShowCommand.run(ctx, ["myphone"])

    FileUtils.rm_rf(tmp_dir)
  end

  it "handles multiple interfaces and requires explicit interface with clear error hint" do
    tmp_dir = File.tempfile("multi_iface_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    wg0_path = File.join(tmp_dir, "wg0.conf")
    File.write(wg0_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = aaaaaaaa=

    # wgctl:name=asteri-m
    [Peer]
    PublicKey = pubKey000000000000000000000000000000000=
    AllowedIPs = 10.13.14.6/32
    CONF
    )

    wg1_path = File.join(tmp_dir, "wg1.conf")
    File.write(wg1_path, <<-CONF
    [Interface]
    Address = 10.13.15.1/24
    ListenPort = 51821
    PrivateKey = cccccccc=

    # wgctl:name=asteri-k
    [Peer]
    PublicKey = pubKey111111111111111111111111111111111=
    AllowedIPs = 10.13.15.6/32
    CONF
    )

    ctx = MultiInterfaceMockContext.new
    ctx.mock_configs = {
      "wg0" => wg0_path,
      "wg1" => wg1_path,
    }

    # 1. When multiple configurations exist and no interface is specified:
    # Must raise error with exact command-specific hint!
    expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl peer show asteri-m -i wg0)") do
      Wgctl::Commands::PeerShowCommand.run(ctx, ["asteri-m"])
    end

    # 2. When interface is specified via context.interface (equivalent to -i / --interface)
    ctx.interface = "wg0"
    Wgctl::Commands::PeerShowCommand.run(ctx, ["asteri-m"]) # Should succeed

    # 3. When interface is specified positionally: wgctl peer show asteri-m wg0
    ctx.interface = nil
    Wgctl::Commands::PeerShowCommand.run(ctx, ["asteri-m", "wg0"]) # Should succeed

    # 4. When checking in an interface where peer does NOT exist:
    ctx.interface = "wg1"
    expect_raises(Exception, "Peer 'asteri-m' not found in interface wg1.") do
      Wgctl::Commands::PeerShowCommand.run(ctx, ["asteri-m"])
    end

    # 5. Peer in wg1 is found when targeting wg1:
    Wgctl::Commands::PeerShowCommand.run(ctx, ["asteri-k"]) # Should succeed

    FileUtils.rm_rf(tmp_dir)
  end
end
