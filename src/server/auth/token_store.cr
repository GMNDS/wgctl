require "json"
require "file_utils"
require "digest/sha256"
require "random"
require "./token"

module Wgctl
  module Server
    module Auth
      class TokenStore
        def self.default_path : String
          if env_path = ENV["WGCTL_TOKENS_FILE"]?
            return env_path unless env_path.empty?
          end

          # If /etc/wireguard exists and is writable, use it (production mode)
          if Dir.exists?("/etc/wireguard")
            begin
              test_file = "/etc/wireguard/.write_test_#{Random::Secure.hex(4)}"
              File.write(test_file, "")
              File.delete(test_file) rescue nil
              return "/etc/wireguard/tokens.json"
            rescue
            end
          end

          # Otherwise fallback to user home directory ~/.config/wgctl/tokens.json
          home = ENV["HOME"]? || ENV["USERPROFILE"]? || "."
          File.join(home, ".config", "wgctl", "tokens.json")
        end

        property path : String
        getter tokens : Array(Token)

        @mutex : Mutex = Mutex.new
        @last_usage_saved_at : Time = Time.utc - 1.day

        def initialize(@path : String = TokenStore.default_path)
          @tokens = [] of Token
          load
        end

        def load
          @mutex.synchronize do
            if File.exists?(@path)
              content = File.read(@path).strip
              unless content.empty?
                token_file = TokenFile.from_json(content) rescue TokenFile.new
                @tokens = token_file.tokens
              end
            else
              @tokens = [] of Token
            end

            ensure_env_tokens
          end
        end

        private def ensure_env_tokens
          raw_token : String? = nil

          if env_file = ENV["WGCTL_TOKEN_FILE"]?
            if File.exists?(env_file)
              content = File.read(env_file).strip
              raw_token = content unless content.empty?
            end
          end

          if raw_token.nil?
            if env_tok = ENV["WGCTL_TOKEN"]?
              raw_token = env_tok.strip unless env_tok.strip.empty?
            end
          end

          if token_str = raw_token
            token_hash = Digest::SHA256.hexdigest(token_str)
            existing = @tokens.find { |t| t.token_hash == token_hash }
            unless existing
              prefix = "#{token_str[0...Math.min(10, token_str.size)]}..."
              env_token = Token.new(
                id: "tok_env_#{Random::Secure.hex(4)}",
                name: "env-secret",
                token_hash: token_hash,
                prefix: prefix,
                created_at: Time.utc,
                expires_at: nil
              )
              @tokens << env_token
              save_internal
            end
          end
        end

        def save
          @mutex.synchronize do
            save_internal
          end
        end

        private def save_internal
          dir = File.dirname(@path)
          FileUtils.mkdir_p(dir) unless Dir.exists?(dir)

          token_file = TokenFile.new(@tokens)
          json_data = token_file.to_pretty_json

          # Atomic write using temporary file
          temp_file = "#{@path}.tmp.#{Random::Secure.hex(4)}"
          File.write(temp_file, json_data)

          # Enforce strict 0600 permissions
          begin
            File.chmod(temp_file, 0o600)
          rescue
          end

          {% if flag?(:windows) %}
            File.delete(@path) if File.exists?(@path)
          {% end %}
          File.rename(temp_file, @path)

          begin
            File.chmod(@path, 0o600)
          rescue
          end
        end

        # Creates a new token, saves store, and returns {Token, raw_token_string}
        def create(name : String, duration : Time::Span? = nil) : Tuple(Token, String)
          raw_secret = Random::Secure.hex(24)
          full_token = "wgctl_tok_#{raw_secret}"
          token_hash = Digest::SHA256.hexdigest(full_token)
          token_id = "tok_#{Random::Secure.hex(4)}"
          prefix = "wgctl_tok_#{raw_secret[0...6]}..."

          now = Time.utc
          expires_at = duration ? (now + duration) : nil

          token = Token.new(
            id: token_id,
            name: name,
            token_hash: token_hash,
            prefix: prefix,
            created_at: now,
            expires_at: expires_at
          )

          @mutex.synchronize do
            @tokens << token
            save_internal
          end

          {token, full_token}
        end

        # Authenticates a raw token against the store, returns Token if valid
        def authenticate(raw_token : String) : Token?
          clean_token = raw_token.strip
          return nil if clean_token.empty?

          calculated_hash = Digest::SHA256.hexdigest(clean_token)

          @mutex.synchronize do
            token = @tokens.find { |t| t.token_hash == calculated_hash }

            if token && token.valid?
              token.record_usage!
              # Debounce disk writes for usage updates (at most once every 60 seconds)
              now = Time.utc
              if (now - @last_usage_saved_at) >= 60.seconds
                @last_usage_saved_at = now
                save_internal
              end
              token
            else
              nil
            end
          end
        end

        # Revokes a token by id or name
        def revoke(id_or_name : String) : Bool
          @mutex.synchronize do
            target = @tokens.find { |t| t.id == id_or_name || t.name == id_or_name }
            if target && !target.revoked?
              target.revoke!
              save_internal
              true
            else
              false
            end
          end
        end

        # Returns all tokens
        def list : Array(Token)
          @mutex.synchronize do
            @tokens.dup
          end
        end
      end
    end
  end
end
