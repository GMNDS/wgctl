require "./spec_helper"
require "file_utils"

describe "wgctl CLI integration" do
  it "runs end-to-end workflow of status, add, client, edit and remove" do
    tmp_dir = File.tempfile("wgctl_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    conf_path = File.join(tmp_dir, "wg0.conf")
    File.write(conf_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51823
    PrivateKey = wBE64BHskDhVYR8fZSatxJaLKzGj4n9O8yxFNoN2u0c=

    # wgctl:name=asteri-c
    # wgctl:description=Contabo Germany
    # wgctl:device=server
    [Peer]
    PublicKey = asteriPublicKey12345678901234567890123456=
    AllowedIPs = 10.13.14.9/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = conf_path

    # 1. Load and check
    iface = ctx.load_interface
    iface.peers.size.should eq(1)
    iface.peers.first.name.should eq("asteri-c")

    # 2. Add peer with auto IP
    ctx.ip = "auto"
    ctx.description = "Mobile Unit"
    ctx.device = "phone"
    ctx.no_apply = true
    Wgctl::Commands::PeerAddCommand.run(ctx, ["mobile"])

    # Reload
    iface_after_add = ctx.load_interface
    iface_after_add.peers.size.should eq(2)
    new_peer = iface_after_add.find_peer("mobile")
    new_peer.should_not be_nil
    new_peer.not_nil!.primary_ip.should eq("10.13.14.2")

    # 3. Edit peer
    ctx.ip = nil
    ctx.description = "Updated Mobile"
    Wgctl::Commands::PeerEditCommand.run(ctx, ["mobile"])
    iface_after_edit = ctx.load_interface
    iface_after_edit.find_peer("mobile").not_nil!.description.should eq("Updated Mobile")

    # 4. Remove peer
    Wgctl::Commands::PeerRemoveCommand.run(ctx, ["mobile"])
    iface_after_remove = ctx.load_interface
    iface_after_remove.peers.size.should eq(1)
    iface_after_remove.find_peer("mobile").should be_nil

    FileUtils.rm_rf(tmp_dir)
  end
end
