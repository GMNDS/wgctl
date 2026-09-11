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

        def initialize(@path : String = TokenStore.default_path)
          @tokens = [] of Token
          load
        end

        def load
          if File.exists?(@path)
            content = File.read(@path).strip
            unless content.empty?
              token_file = TokenFile.from_json(content) rescue TokenFile.new
              @tokens = token_file.tokens
            end
          else
            @tokens = [] of Token
          end
        end

        def save
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

          @tokens << token
          save
          {token, full_token}
        end

        # Authenticates a raw token against the store, returns Token if valid
        def authenticate(raw_token : String) : Token?
          clean_token = raw_token.strip
          return nil if clean_token.empty?

          calculated_hash = Digest::SHA256.hexdigest(clean_token)
          token = @tokens.find { |t| t.token_hash == calculated_hash }

          if token && token.valid?
            token.record_usage!
            save
            token
          else
            nil
          end
        end

        # Revokes a token by id or name
        def revoke(id_or_name : String) : Bool
          target = @tokens.find { |t| t.id == id_or_name || t.name == id_or_name }
          if target && !target.revoked?
            target.revoke!
            save
            true
          else
            false
          end
        end

        # Returns all tokens
        def list : Array(Token)
          @tokens
        end
      end
    end
  end
end
