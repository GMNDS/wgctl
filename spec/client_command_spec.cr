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

  it "includes PresharedKey in client config when peer has preshared_key" do
    tmp_dir = File.tempfile("client_test_psk", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "astrum-sc.conf")
    test_psk = "yD8BqXhXFjXq4rK7wX+9jR0tQ1lE5mP8yZ3uI2oA4s="
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=astrum-sc
    [Peer]
    PublicKey = astrum-public-key
    PresharedKey = #{test_psk}
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path

    Wgctl::Commands::ClientCommand.run(ctx, ["astrum-sc"])

    output = File.read(output_path)
    output.should contain("PublicKey = ")
    output.should contain("PresharedKey = #{test_psk}")
    output.should contain("AllowedIPs = 0.0.0.0/0, ::/0")

    FileUtils.rm_rf(tmp_dir)
  end

  it "omits PresharedKey when peer has no preshared_key" do
    tmp_dir = File.tempfile("client_test_nopsk", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "regular.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=regular
    [Peer]
    PublicKey = regular-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path

    Wgctl::Commands::ClientCommand.run(ctx, ["regular"])

    output = File.read(output_path)
    output.should_not contain("PresharedKey")

    FileUtils.rm_rf(tmp_dir)
  end

  it "renders stored client_private_key in client configuration" do
    tmp_dir = File.tempfile("client_test_stored_priv", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    output_path = File.join(tmp_dir, "phone.conf")
    priv_key = "aGVsYW1vcmV4YW1wbGVwcml2YXRla2V5MTIzNDU2Nzg5MD0="
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=phone
    # wgctl:client_private_key=#{priv_key}
    [Peer]
    PublicKey = phone-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.output_file = output_path

    Wgctl::Commands::ClientCommand.run(ctx, ["phone"])

    output = File.read(output_path)
    output.should contain("PrivateKey = #{priv_key}")
    output.should_not contain("<REPLACE_WITH_CLIENT_PRIVATE_KEY>")

    FileUtils.rm_rf(tmp_dir)
  end

  it "auto-generates valid 32-byte keypair when generating QR code for peer without stored key" do
    tmp_dir = File.tempfile("client_test_qr_auto_rotate", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    config_path = File.join(tmp_dir, "wg0.conf")
    File.write(config_path, <<-CONF
    [Interface]
    Address = 10.13.14.1/24
    ListenPort = 51820
    PrivateKey = server-private-key

    # wgctl:name=nopriv
    [Peer]
    PublicKey = nopriv-public-key
    AllowedIPs = 10.13.14.2/32
    CONF
    )

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = config_path
    ctx.qr_code = true
    ctx.no_apply = true

    # Should not raise, should auto-rotate and generate a valid key
    Wgctl::Commands::ClientCommand.run(ctx, ["nopriv"])

    # Reload config to verify the new private key and public key were saved
    updated_conf = File.read(config_path)
    updated_conf.should contain("# wgctl:client_private_key=")
    updated_conf.should_not contain("nopriv-public-key")

    FileUtils.rm_rf(tmp_dir)
  end
end
