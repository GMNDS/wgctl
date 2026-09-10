require "./spec_helper"

describe Wgctl::Config::Validator do
  it "detects duplicate IPs and peers without names" do
    sample = <<-CONF
    [Interface]
    Address = 10.13.14.1/24

    # wgctl:name=peer1
    [Peer]
    PublicKey = pub1=
    AllowedIPs = 10.13.14.2/32

    # Peer without name
    [Peer]
    PublicKey = pub2=
    AllowedIPs = 10.13.14.2/32
    CONF

    iface = Wgctl::Config::Parser.parse_string(sample, "wg0")
    report = Wgctl::Config::Validator.validate(iface)

    report.valid?.should be_false
    report.error_count.should be >= 1
    report.warning_count.should be >= 1

    has_dup_error = report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Error && i.message.includes?("10.13.14.2/32 is assigned to multiple peers") }
    has_dup_error.should be_true

    has_warn_name = report.issues.any? { |i| i.severity == Wgctl::Config::Severity::Warning && i.message.includes?("has no wgctl:name") }
    has_warn_name.should be_true
  end
end
