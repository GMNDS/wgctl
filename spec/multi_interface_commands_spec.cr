require "./spec_helper"
require "file_utils"

class MultiCmdMockContext < Wgctl::CLI::Context
  property mock_configs : Hash(String, String) = Hash(String, String).new

  def available_configs : Hash(String, String)
    @mock_configs
  end
end

describe "Multi-interface support across all commands" do
  tmp_dir = File.tempfile("multi_cmd_test", "").path
  File.delete(tmp_dir) rescue nil
  Dir.mkdir_p(tmp_dir)

  wg0_path = File.join(tmp_dir, "wg0.conf")
  File.write(wg0_path, <<-CONF
  [Interface]
  Address = 10.13.14.1/24
  ListenPort = 51820
  PrivateKey = aaaaaaaa=

  # wgctl:name=client0
  [Peer]
  PublicKey = pub0000000000000000000000000000000000000000=
  AllowedIPs = 10.13.14.2/32
  CONF
  )

  wg1_path = File.join(tmp_dir, "wg1.conf")
  File.write(wg1_path, <<-CONF
  [Interface]
  Address = 10.13.15.1/24
  ListenPort = 51821
  PrivateKey = cccccccc=

  # wgctl:name=client1
  [Peer]
  PublicKey = pub1111111111111111111111111111111111111111=
  AllowedIPs = 10.13.15.2/32
  CONF
  )

  mock_configs = {
    "wg0" => wg0_path,
    "wg1" => wg1_path,
  }

  describe "StatusCommand" do
    it "requires interface and gives helpful hint" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs

      expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl status -i wg0)") do
        Wgctl::Commands::StatusCommand.run(ctx, [] of String)
      end
    end

    it "accepts interface via -i / context.interface" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      ctx.interface = "wg0"
      Wgctl::Commands::StatusCommand.run(ctx, [] of String)
    end

    it "accepts interface via positional argument" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      Wgctl::Commands::StatusCommand.run(ctx, ["wg1"])
    end
  end

  describe "PeersCommand" do
    it "requires interface and gives helpful hint" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs

      expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl peers -i wg0)") do
        Wgctl::Commands::PeersCommand.run(ctx, [] of String)
      end
    end

    it "accepts interface via -i / context.interface" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      ctx.interface = "wg0"
      Wgctl::Commands::PeersCommand.run(ctx, [] of String)
    end

    it "accepts interface via positional argument" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      Wgctl::Commands::PeersCommand.run(ctx, ["wg1"])
    end
  end

  describe "CheckCommand" do
    it "requires interface and gives helpful hint" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs

      expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl check -i wg0)") do
        Wgctl::Commands::CheckCommand.run(ctx, [] of String)
      end
    end

    it "accepts interface via -i / context.interface" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      ctx.interface = "wg0"
      Wgctl::Commands::CheckCommand.run(ctx, [] of String)
    end

    it "accepts interface via positional argument" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      Wgctl::Commands::CheckCommand.run(ctx, ["wg1"])
    end
  end

  describe "ApplyCommand" do
    it "requires interface and gives helpful hint" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs

      expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl apply -i wg0)") do
        Wgctl::Commands::ApplyCommand.run(ctx, [] of String)
      end
    end
  end

  describe "MigrateCommand" do
    it "requires interface and gives helpful hint" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs

      expect_raises(Exception, "Multiple WireGuard configurations found (wg0, wg1). Please specify an interface with -i or --interface (e.g. wgctl migrate -i wg0)") do
        Wgctl::Commands::MigrateCommand.run(ctx, [] of String)
      end
    end

    it "accepts interface via -i / context.interface in dry-run" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      ctx.interface = "wg0"
      ctx.dry_run = true
      Wgctl::Commands::MigrateCommand.run(ctx, [] of String)
    end
  end

  describe "InitCommand with -i" do
    it "respects -i / context.interface instead of defaulting to wg0" do
      init_dir = File.tempfile("init_multi_test", "").path
      File.delete(init_dir) rescue nil
      Dir.mkdir_p(init_dir)

      custom_conf = File.join(init_dir, "wg2.conf")
      ctx = Wgctl::CLI::Context.new
      ctx.config_file = custom_conf
      ctx.interface = "wg2"
      ctx.non_interactive = true
      ctx.skip_pkg_install = true
      ctx.no_firewall = true
      ctx.no_start = true

      # Should initialize without error and create wg2.conf
      Wgctl::Commands::InitCommand.run(ctx, [] of String)
      File.exists?(custom_conf).should be_true

      FileUtils.rm_rf(init_dir)
    end
  end

  describe "MenuCommand with -i" do
    it "pre-selects interface specified via -i / context.interface" do
      ctx = MultiCmdMockContext.new
      ctx.mock_configs = mock_configs
      ctx.interface = "wg1"

      menu = Wgctl::Commands::MenuCommand.new(ctx, [] of String)
      menu.selected_iface_name.should eq("wg1")
    end
  end
end
