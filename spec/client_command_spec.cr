require "./spec_helper"
require "file_utils"
require "../src/commands/client_command"

describe "wgctl client" do
  it "exports full-tunnel AllowedIPs" do
    tmp_dir = File.tempfile("client_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "android.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=android
    [Peer]
    PublicKey = android-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path

    Wgctl::Commands::ClientCommand.run(ctx, ["android"])

    output = File.read(output_path)
    output.should contain("AllowedIPs = 0.0.0.0/0, ::/0")
    output.should_not contain("AllowedIPs = 10.13.14.0/24")

    FileUtils.rm_rf(tmp_dir)
  end

  it "exports split-tunnel VPN-only AllowedIPs with --allowed-ips vpn" do
    tmp_dir = File.tempfile("client_test_vpn", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "android.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=android
    [Peer]
    PublicKey = android-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path
    ctx.client_allowed_ips = "vpn"

    Wgctl::Commands::ClientCommand.run(ctx, ["android"])

    output = File.read(output_path)
    output.should contain("AllowedIPs = 10.13.14.0/24")
    output.should_not contain("0.0.0.0/0")

    FileUtils.rm_rf(tmp_dir)
  end

  it "exports custom CIDRs list with --allowed-ips" do
    tmp_dir = File.tempfile("client_test_custom", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "android.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=android
    [Peer]
    PublicKey = android-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path
    ctx.client_allowed_ips = "10.13.14.0/24, 192.168.10.0/24"

    Wgctl::Commands::ClientCommand.run(ctx, ["android"])

    output = File.read(output_path)
    output.should contain("AllowedIPs = 10.13.14.0/24, 192.168.10.0/24")

    FileUtils.rm_rf(tmp_dir)
  end

  it "respects peer metadata client_allowed_ips" do
    tmp_dir = File.tempfile("client_test_meta", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "android.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=android
    # wgctl:client_allowed_ips=vpn
    [Peer]
    PublicKey = android-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path

    Wgctl::Commands::ClientCommand.run(ctx, ["android"])

    output = File.read(output_path)
    output.should contain("AllowedIPs = 10.13.14.0/24")

    FileUtils.rm_rf(tmp_dir)
  end
end
