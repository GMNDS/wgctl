require "http/server"

module Wgctl
  module Server
    class CORSHandler
      include HTTP::Handler

      property allowed_origin : String

      def initialize(@allowed_origin : String = "*")
      end

      def call(context : HTTP::Server::Context)
        context.response.headers["Access-Control-Allow-Origin"] = @allowed_origin
        context.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
        context.response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-Requested-With"
        context.response.headers["Access-Control-Max-Age"] = "86400"

        if context.request.method == "OPTIONS"
          context.response.status_code = 204
          return
        end

        call_next(context)
      end
    end
  end
end
