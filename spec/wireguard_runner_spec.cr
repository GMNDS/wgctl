require "./spec_helper"

describe Wgctl::WireGuard::Runner do
  describe ".writable_dir?" do
    it "returns true for a writable directory" do
      test_dir = File.join(Dir.tempdir, "runner_writable_test_#{Random::Secure.hex(4)}")
      Dir.mkdir_p(test_dir)
      begin
        Wgctl::WireGuard::Runner.writable_dir?(test_dir).should be_true
      ensure
        FileUtils.rm_rf(test_dir)
      end
    end

    it "returns false for a non-existent directory" do
      non_existent = File.join(Dir.tempdir, "non_existent_#{Random::Secure.hex(8)}")
      Wgctl::WireGuard::Runner.writable_dir?(non_existent).should be_false
    end
  end

  describe ".syncconf_temp_path" do
    it "places temp file in the config directory when writable to comply with AppArmor" do
      test_dir = File.join(Dir.tempdir, "apparmor_test_#{Random::Secure.hex(4)}")
      Dir.mkdir_p(test_dir)
      config_path = File.join(test_dir, "wg0.conf")

      begin
        temp_path = Wgctl::WireGuard::Runner.syncconf_temp_path("wg0", config_path)
        File.dirname(temp_path).should eq(test_dir)
        File.basename(temp_path).should start_with(".wgctl-sync-wg0-")
        File.basename(temp_path).should end_with(".conf")
      ensure
        FileUtils.rm_rf(test_dir)
      end
    end

    it "falls back to Dir.tempdir when config directory does not exist or is not writable" do
      fake_config = "/non/existent/wireguard/dir/wg0.conf"
      temp_path = Wgctl::WireGuard::Runner.syncconf_temp_path("wg0", fake_config)

      # Should fall back to Dir.tempdir
      File.dirname(temp_path).should eq(Dir.tempdir)
      File.basename(temp_path).should start_with(".wgctl-sync-wg0-")
      File.basename(temp_path).should end_with(".conf")
    end
  end
end
