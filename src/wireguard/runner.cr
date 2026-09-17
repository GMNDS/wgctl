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

        # 2. Write stripped configuration to a secure temporary file
        temp_file = File.tempfile("wgctl-strip-#{interface_name}", ".conf")
        begin
          File.chmod(temp_file.path, 0o600)
          File.write(temp_file.path, stripped_content)

          # 3. Run `wg syncconf <interface_name> <temp_file>`
          sync_stdout = IO::Memory.new
          sync_stderr = IO::Memory.new
          sync_status = Process.run("wg", ["syncconf", interface_name, temp_file.path], output: sync_stdout, error: sync_stderr)

          if sync_status.success?
            {true, "Applied configuration to active interface #{interface_name} via wg syncconf."}
          else
            err = sync_stderr.to_s.strip
            {false, "wg syncconf failed: #{err}"}
          end
        ensure
          temp_file.delete rescue nil
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
