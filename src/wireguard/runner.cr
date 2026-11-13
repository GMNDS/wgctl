require "process"
require "file_utils"
require "./dump_parser"
require "../models/interface"

module Wgctl
  module WireGuard
    class Runner
      # Check if 'wg' binary is installed and executable
      def self.wg_available? : Bool
        !Process.find_executable("wg").nil?
      rescue
        false
      end

      # Runs `wg show interfaces` to find active WireGuard interfaces
      def self.list_active_interfaces : Array(String)
        stdout = IO::Memory.new
        status = Process.run("wg", ["show", "interfaces"], output: stdout)
        if status.success?
          stdout.to_s.strip.split(/\s+/).reject(&.empty?)
        else
          [] of String
        end
      rescue
        [] of String
      end

      # Runs `wg show <interface> dump`
      def self.fetch_dump(interface_name : String) : String?
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run("wg", ["show", interface_name, "dump"], output: stdout, error: stderr)
        if status.success?
          stdout.to_s
        else
          nil
        end
      rescue
        nil
      end

      # Returns true if directory exists and is writable
      def self.writable_dir?(dir : String) : Bool
        return false unless Dir.exists?(dir)
        test_file = File.join(dir, ".wgctl_write_test_#{Random::Secure.hex(4)}")
        File.write(test_file, "")
        File.delete(test_file)
        true
      rescue
        false
      end

      # Returns the temporary file path used for syncconf.
      # Placed in the configuration directory when writable to satisfy AppArmor restrictions.
      def self.syncconf_temp_path(interface_name : String, config_path : String) : String
        conf_dir = File.dirname(File.expand_path(config_path))
        target_dir = writable_dir?(conf_dir) ? conf_dir : Dir.tempdir
        temp_filename = ".wgctl-sync-#{interface_name}-#{Process.pid}-#{Random::Secure.hex(4)}.conf"
        File.join(target_dir, temp_filename)
      end

      # Syncs live interface using `wg-quick strip` and `wg syncconf`
      # without dropping existing tunnels!
      def self.apply_syncconf(interface_name : String, config_path : String) : Tuple(Bool, String)
        # 1. Run `wg-quick strip <config_path>` to produce pure wg configuration
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        strip_status = Process.run("wg-quick", ["strip", config_path], output: stdout, error: stderr)
        unless strip_status.success?
          return {false, "wg-quick strip failed: #{stderr.to_s.strip}"}
        end

        # Filter stripped content: wg syncconf strictly only allows ListenPort, PrivateKey, FwMark
        # in the [Interface] section. If any unrecognized line (like Endpoint) slipped through, filter it out.
        cleaned_lines = [] of String
        in_interface_section = false

        stdout.to_s.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\[\s*([a-zA-Z0-9_-]+)\s*\]$/
            in_interface_section = ($1.downcase == "interface")
            cleaned_lines << line
            next
          end

          if in_interface_section && stripped =~ /^([^=]+)=(.*)$/
            key = $1.strip.downcase
            unless ["listenport", "privatekey", "fwmark"].includes?(key)
              next
            end
          end

          cleaned_lines << line
        end

        stripped_content = cleaned_lines.join("\n")

        # 2. Write stripped configuration to a secure temporary file in the configuration directory.
        # Ubuntu/Debian default AppArmor profiles confine `/usr/bin/wg` to only read files
        # within `/etc/wireguard/**`. Writing to `/tmp` results in `fopen: Permission denied`
        # even when executed under sudo/root.
        # Placing the temporary stripped file in the same directory as config_path (e.g. /etc/wireguard/)
        # ensures `wg` is granted read permissions by AppArmor.
        temp_path = syncconf_temp_path(interface_name, config_path)

        begin
          File.write(temp_path, stripped_content)
          File.chmod(temp_path, 0o600)

          # 3. Run `wg syncconf <interface_name> <temp_file>`
          sync_stdout = IO::Memory.new
          sync_stderr = IO::Memory.new
          sync_status = Process.run("wg", ["syncconf", interface_name, temp_path], output: sync_stdout, error: sync_stderr)

          if sync_status.success?
            {true, "Applied configuration to active interface #{interface_name} via wg syncconf."}
          else
            err = sync_stderr.to_s.strip
            if err.includes?("fopen: Permission denied") || err.includes?("Permission denied")
              {false, "wg syncconf failed: #{err} (AppArmor may be confining /usr/bin/wg. Check 'sudo dmesg | grep -i apparmor' or run 'sudo aa-complain /etc/apparmor.d/wg')"}
            else
              {false, "wg syncconf failed: #{err}"}
            end
          end
        ensure
          File.delete(temp_path) if temp_path && File.exists?(temp_path) rescue nil
        end
      rescue ex
        {false, "Failed to apply configuration: #{ex.message}"}
      end

      # Generates a terminal QR code using `qrencode`
      def self.generate_qr_terminal(content : String) : String
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        process = Process.new(
          "qrencode",
          ["-t", "ansiutf8"],
          input: Process::Redirect::Pipe,
          output: stdout,
          error: stderr
        )
        process.input.print(content)
        process.input.close
        status = process.wait

        if status.success?
          stdout.to_s
        else
          raise "qrencode failed: #{stderr.to_s.strip}"
        end
      rescue ex
        raise "QR code generation requires 'qrencode' to be installed. Error: #{ex.message}"
      end
    end
  end
end
