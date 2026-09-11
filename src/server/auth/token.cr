require "json"
require "time"

module Wgctl
  module Server
    module Auth
      class Token
        include JSON::Serializable

        property id : String
        property name : String
        property token_hash : String
        property prefix : String
        property created_at : Time
        property expires_at : Time?
        property revoked_at : Time?
        property last_used_at : Time?

        def initialize(
          @id : String,
          @name : String,
          @token_hash : String,
          @prefix : String,
          @created_at : Time = Time.utc,
          @expires_at : Time? = nil,
          @revoked_at : Time? = nil,
          @last_used_at : Time? = nil
        )
        end

        def expired?(now : Time = Time.utc) : Bool
          if exp = @expires_at
            return now >= exp
          end
          false
        end

        def revoked? : Bool
          !@revoked_at.nil?
        end

        def valid?(now : Time = Time.utc) : Bool
          !revoked? && !expired?(now)
        end

        def revoke!(now : Time = Time.utc)
          @revoked_at = now
        end

        def record_usage!(now : Time = Time.utc)
          @last_used_at = now
        end
      end

      struct TokenFile
        include JSON::Serializable

        property tokens : Array(Token)

        def initialize(@tokens : Array(Token) = [] of Token)
        end
      end
    end
  end
end
