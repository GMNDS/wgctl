require "process"

module Wgctl
  module WireGuard
    class PackageManager
      REQUIRED_TOOLS = ["wg", "wg-quick", "iptables"]
      OPTIONAL_TOOLS = ["qrencode"]

      # Checks which required and recommended tools are currently missing from PATH
      def self.missing_tools : Array(String)
        (REQUIRED_TOOLS + OPTIONAL_TOOLS).reject do |tool|
          !Process.find_executable(tool).nil?
        end
      rescue
        REQUIRED_TOOLS + OPTIONAL_TOOLS
      end

      # Returns true if all required tools (and recommended qrencode) are present
      def self.dependencies_installed? : Bool
        missing_tools.empty?
      end

      # Returns true if the core wireguard tools are present
      def self.core_installed? : Bool
        REQUIRED_TOOLS.all? { |t| !Process.find_executable(t).nil? }
      rescue
        false
      end

      # Detects Linux distribution family from /etc/os-release
      def self.detect_distro : Symbol
        if File.exists?("/etc/os-release")
          content = File.read("/etc/os-release")
          id = ""
          id_like = ""

          content.each_line do |line|
            stripped = line.strip
            if stripped =~ /^ID=["']?([^"']+)["']?/
              id = $1.downcase
            elsif stripped =~ /^ID_LIKE=["']?([^"']+)["']?/
              id_like = $1.downcase
            end
          end

          case id
          when "ubuntu"
            return :ubuntu
          when "debian", "raspbian"
            return :debian
          when "centos", "rocky", "almalinux", "rhel", "ol"
            return :rhel
          when "fedora"
            return :fedora
          when "arch", "manjaro", "endeavouros"
            return :arch
          when "alpine"
            return :alpine
          end

          if id_like.includes?("debian") || id_like.includes?("ubuntu")
            return :debian
          elsif id_like.includes?("rhel") || id_like.includes?("centos")
            return :rhel
          elsif id_like.includes?("fedora")
            return :fedora
          elsif id_like.includes?("arch")
            return :arch
          end
        end

        if File.exists?("/etc/debian_version")
          return :debian
        elsif File.exists?("/etc/almalinux-release") || File.exists?("/etc/rocky-release") || File.exists?("/etc/centos-release") || File.exists?("/etc/redhat-release")
          return :rhel
        elsif File.exists?("/etc/fedora-release")
          return :fedora
        elsif File.exists?("/etc/arch-release")
          return :arch
        elsif File.exists?("/etc/alpine-release")
          return :alpine
        end

        :unknown
      rescue
        :unknown
      end

      # Check if running as superuser (root)
      def self.root? : Bool
        {% if flag?(:windows) %}
          false
        {% else %}
          LibC.getuid == 0
        {% end %}
      rescue
        stdout = IO::Memory.new
        status = Process.run("id", ["-u"], output: stdout)
        status.success? && stdout.to_s.strip == "0"
      end

      # Automatically installs wireguard, iptables, and qrencode based on the Linux distro
      def self.install_dependencies(inherit_output : Bool = true) : Tuple(Bool, String)
        missing = missing_tools
        return {true, "All required system dependencies are already installed."} if missing.empty?

        # Check root permission
        unless root?
          return {false, "Root privileges required to install system packages. Please run with 'sudo' or as root."}
        end

        distro = detect_distro
        if distro == :unknown
          return {false, "Unsupported Linux distribution. Please manually install: #{missing.join(", ")}"}
        end

        output_mode = inherit_output ? Process::Redirect::Inherit : Process::Redirect::Pipe
        error_mode = inherit_output ? Process::Redirect::Inherit : Process::Redirect::Pipe

        case distro
        when :ubuntu, :debian
          puts "Running: apt-get update..."
          status = Process.run("apt-get", ["update"], output: output_mode, error: error_mode)
          unless status.success?
            return {false, "apt-get update failed."}
          end

          packages = ["wireguard", "wireguard-tools", "iptables", "qrencode"]
          puts "Running: apt-get install -y #{packages.join(" ")}..."
          status = Process.run("apt-get", ["install", "-y"] + packages, output: output_mode, error: error_mode)
          unless status.success?
            return {false, "apt-get install failed."}
          end

        when :rhel
          puts "Running: dnf install -y epel-release..."
          Process.run("dnf", ["install", "-y", "epel-release"], output: output_mode, error: error_mode) rescue nil

          packages = ["wireguard-tools", "iptables", "qrencode"]
          puts "Running: dnf install -y #{packages.join(" ")}..."
          status = Process.run("dnf", ["install", "-y"] + packages, output: output_mode, error: error_mode)
          unless status.success?
            return {false, "dnf install failed."}
          end

        when :fedora
          packages = ["wireguard-tools", "iptables", "qrencode"]
          puts "Running: dnf install -y #{packages.join(" ")}..."
          status = Process.run("dnf", ["install", "-y"] + packages, output: output_mode, error: error_mode)
          unless status.success?
            return {false, "dnf install failed."}
          end

        when :arch
          packages = ["wireguard-tools", "iptables", "qrencode"]
          puts "Running: pacman -Sy --noconfirm #{packages.join(" ")}..."
          status = Process.run("pacman", ["-Sy", "--noconfirm"] + packages, output: output_mode, error: error_mode)
          unless status.success?
            return {false, "pacman install failed."}
          end

        when :alpine
          packages = ["wireguard-tools", "iptables", "qrencode"]
          puts "Running: apk add --no-cache #{packages.join(" ")}..."
          status = Process.run("apk", ["add", "--no-cache"] + packages, output: output_mode, error: error_mode)
          unless status.success?
            return {false, "apk add failed."}
          end
        end

        # Verify installation
        remaining = missing_tools.select { |t| REQUIRED_TOOLS.includes?(t) }
        if remaining.empty?
          {true, "System packages installed successfully."}
        else
          {false, "Some required packages could not be installed: #{remaining.join(", ")}"}
        end
      rescue ex
        {false, "Exception while installing packages: #{ex.message}"}
      end
    end
  end
end
