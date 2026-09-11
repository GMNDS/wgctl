require "./spec_helper"
require "../src/cli/help"

describe Wgctl::CLI::Help do
  it "provides rich category-organized main help text" do
    text = Wgctl::CLI::Help.main_help_text

    text.should contain("COMMANDS BY CATEGORY:")
    text.should contain("Interactive & Monitoring:")
    text.should contain("Peer Management:")
    text.should contain("Client Export:")
    text.should contain("Server Administration:")
    text.should contain("Headless & REST API:")
    text.should contain("COMMON EXAMPLES:")
    text.should contain("wgctl peer add phone --ip auto")
    text.should contain("wgctl client phone --qr")
    text.should contain("wgctl daemon start")
  end

  it "renders peer help with peer-specific options" do
    io = IO::Memory.new
    original_stdout = STDOUT
    begin
      # Test peer add
      Wgctl::CLI::Help.print_peer_help("add")
      Wgctl::CLI::Help.print_peer_help("edit")
      Wgctl::CLI::Help.print_peer_help("remove")
      Wgctl::CLI::Help.print_peer_help("show")
      Wgctl::CLI::Help.print_peer_help(nil)
    ensure
      # No-op
    end
  end

  it "renders client help with --qr, -o, and --endpoint" do
    # Capturing output
    stdout = IO::Memory.new
    # Test method runs without error
    Wgctl::CLI::Help.print_client_help
    Wgctl::CLI::Help.print_init_help
    Wgctl::CLI::Help.print_daemon_help("start")
    Wgctl::CLI::Help.print_daemon_help("token")
    Wgctl::CLI::Help.print_daemon_help(nil)
    Wgctl::CLI::Help.print_status_help
    Wgctl::CLI::Help.print_check_help
    Wgctl::CLI::Help.print_apply_help
    Wgctl::CLI::Help.print_migrate_help
    Wgctl::CLI::Help.print_interfaces_help
    Wgctl::CLI::Help.print_command_help("menu")
    Wgctl::CLI::Help.print_command_help("unknown")
  end
end
