require "./spec_helper"
require "../src/wireguard/package_manager"

describe Wgctl::WireGuard::PackageManager do
  it "detects system distribution" do
    distro = Wgctl::WireGuard::PackageManager.detect_distro
    distro.is_a?(Symbol).should be_true
  end

  it "inspects missing tools" do
    missing = Wgctl::WireGuard::PackageManager.missing_tools
    missing.is_a?(Array(String)).should be_true
  end

  it "checks if dependencies or core are installed" do
    deps = Wgctl::WireGuard::PackageManager.dependencies_installed?
    core = Wgctl::WireGuard::PackageManager.core_installed?
    (deps == true || deps == false).should be_true
    (core == true || core == false).should be_true
  end
end
