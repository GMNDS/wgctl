require "json"
require "file_utils"

module Wgctl
  module Client
    struct RemoteProfile
      include JSON::Serializable

      property url : String
      property token : String
      property default_interface : String?

      def initialize(@url : String, @token : String, @default_interface : String? = nil)
      end
    end

    class Config
      include JSON::Serializable

      property active_profile : String?
      property profiles : Hash(String, RemoteProfile) = Hash(String, RemoteProfile).new

      def initialize(@active_profile : String? = nil, @profiles : Hash(String, RemoteProfile) = Hash(String, RemoteProfile).new)
      end

      # Path to remote profiles configuration (~/.config/wgctl/remote.json)
      def self.config_path : String
        base_dir = ENV["WGCTL_CONFIG_DIR"]? || begin
          home = ENV["HOME"]? || ENV["USERPROFILE"]? || "."
          File.join(home, ".config", "wgctl")
        end
        File.join(base_dir, "remote.json")
      end

      # Loads existing config or returns new instance if not exists
      def self.load : Config
        path = config_path
        if File.exists?(path)
          from_json(File.read(path))
        else
          new
        end
      rescue
        new
      end

      # Saves configuration with 0600 permissions
      def save : Nil
        path = self.class.config_path
        dir = File.dirname(path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        File.write(path, self.to_pretty_json)
        File.chmod(path, 0o600)
      end

      # Returns currently active profile if set
      def current_profile : RemoteProfile?
        if name = @active_profile
          @profiles[name]?
        else
          nil
        end
      end

      def add_profile(name : String, profile : RemoteProfile, set_active : Bool = true)
        @profiles[name] = profile
        @active_profile = name if set_active || @active_profile.nil?
        save
      end

      def remove_profile(name : String) : Bool
        if @profiles.delete(name)
          if @active_profile == name
            @active_profile = @profiles.keys.first?
          end
          save
          true
        else
          false
        end
      end
    end
  end
end
