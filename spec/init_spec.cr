require "./spec_helper"
require "file_utils"

describe "wgctl init" do
  it "generates server configuration with NAT rules and first client" do
    tmp_dir = File.tempfile("init_test", "").path
    File.delete(tmp_dir) rescue nil
    Dir.mkdir_p(tmp_dir)

    server_conf_path = File.join(tmp_dir, "wg0.conf")

    ctx = Wgctl::CLI::Context.new
    ctx.config_file = server_conf_path
    ctx.wan_interface = "eth0"
    ctx.public_ip = "198.51.100.1"
    ctx.port = 51820
    ctx.subnet = "10.13.14.1/24"
    ctx.dns = "1.1.1.1, 1.0.0.1"
    ctx.first_client = "myphone"
    ctx.non_interactive = true
    ctx.no_start = true

    # Run init
    Wgctl::Commands::InitCommand.run(ctx, ["wg0"])

    File.exists?(server_conf_path).should be_true
    content = File.read(server_conf_path)

    content.should contain("[Interface]")
    content.should contain("Address = 10.13.14.1/24")
    content.should contain("ListenPort = 51820")
    content.should contain("PostUp = iptables -A FORWARD")
    content.should contain("PostDown = iptables -D FORWARD")
    content.should contain("# wgctl:name=myphone")
    content.should contain("AllowedIPs = 10.13.14.2/32")

    # Client config should have been created in current directory
    client_file = "myphone.conf"
    if File.exists?(client_file)
      client_content = File.read(client_file)
      client_content.should contain("[Interface]")
      client_content.should contain("Address = 10.13.14.2/32")
      client_content.should contain("Endpoint = 198.51.100.1:51820")
      client_content.should contain("AllowedIPs = 0.0.0.0/0, ::/0")
      File.delete(client_file) rescue nil
    end

    FileUtils.rm_rf(tmp_dir)
  end
end
