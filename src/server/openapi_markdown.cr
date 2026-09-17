require "json"
require "./openapi"

module Wgctl
  module Server
    class OpenAPIMarkdown
      def self.generate(json_spec : String? = nil) : String
        raw_json = json_spec || OpenAPISpec.generate
        spec = JSON.parse(raw_json)

        io = IO::Memory.new

        info = spec["info"]
        title = info["title"]?.try(&.as_s?) || "API Reference"
        version = info["version"]?.try(&.as_s?) || "1.0.0"
        description = info["description"]?.try(&.as_s?) || ""

        io.puts "# #{title} (v#{version})"
        io.puts ""
        io.puts "> **Base URL:** `http(s)://<host>:<port>/api/v1`  "
        io.puts "> **Porta padrão:** `7443`  "
        io.puts "> **Content-Type:** `application/json` (request e response)  "
        io.puts "> **Autenticação:** Bearer Token (todas as rotas exceto `/health`)"
        io.puts ""

        if !description.empty?
          io.puts description
          io.puts ""
        end

        io.puts "---"
        io.puts ""
        io.puts "## Autenticação"
        io.puts ""
        io.puts "Todas as rotas (exceto `/health`) exigem autenticação via token Bearer no header `Authorization` ou no query parameter `?token=<token>`:"
        io.puts ""
        io.puts "```http"
        io.puts "Authorization: Bearer <token>"
        io.puts "```"
        io.puts ""
        io.puts "Para gerar um novo token de acesso no servidor WireGuard:"
        io.puts "```bash"
        io.puts "wgctl daemon token create --name \"meu-app\" --expires 30d"
        io.puts "```"
        io.puts ""
        io.puts "---"
        io.puts ""
        io.puts "## Formato de Resposta Padrão"
        io.puts ""
        io.puts "Todas as respostas da API seguem um formato envelope uniforme:"
        io.puts ""
        io.puts "**Sucesso (HTTP 2xx):**"
        io.puts "```json"
        io.puts "{"
        io.puts "  \"success\": true,"
        io.puts "  \"data\": { ... }"
        io.puts "}"
        io.puts "```"
        io.puts ""
        io.puts "**Erro (HTTP 4xx / 5xx):**"
        io.puts "```json"
        io.puts "{"
        io.puts "  \"success\": false,"
        io.puts "  \"error\": {"
        io.puts "    \"code\": \"ERROR_CODE\","
        io.puts "    \"message\": \"Mensagem explicativa do erro\""
        io.puts "  }"
        io.puts "}"
        io.puts "```"
        io.puts ""
        io.puts "---"
        io.puts ""

        # ─── Table of Contents ────────────────────────────────────────────────
        io.puts "## Índice de Endpoints"
        io.puts ""
        io.puts "| Método | Rota | Descrição | Autenticação |"
        io.puts "|:---|:---|:---|:---:|"

        paths = spec["paths"]?.try(&.as_h) || Hash(String, JSON::Any).new
        http_verbs = ["get", "post", "put", "patch", "delete", "options", "head"]

        paths.each do |path_key, methods|
          methods.as_h.each do |http_verb, operation|
            next unless http_verbs.includes?(http_verb.downcase)

            verb_upper = http_verb.upcase
            summary = operation["summary"]?.try(&.as_s?) || ""
            has_auth = operation["security"]?.nil? || (operation["security"]?.try(&.as_a.size) || 0) > 0
            auth_badge = has_auth ? "Sim" : "Não"

            anchor = "#{verb_upper.downcase}-#{path_key.gsub("/", "").gsub("{", "").gsub("}", "").gsub("_", "-")}"
            io.puts "| `#{verb_upper}` | [#{path_key}](##{anchor}) | #{summary} | #{auth_badge} |"
          end
        end
        io.puts ""
        io.puts "---"
        io.puts ""

        # ─── Group by Tags ────────────────────────────────────────────────────
        # Group operations by tags: Tag -> Array of {verb, path, operation, path_params}
        tagged_operations = Hash(String, Array(Tuple(String, String, JSON::Any, Array(JSON::Any)))).new

        paths.each do |path_key, methods|
          path_params = methods["parameters"]?.try(&.as_a) || [] of JSON::Any

          methods.as_h.each do |http_verb, operation|
            next unless http_verbs.includes?(http_verb.downcase)

            tags = operation["tags"]?.try(&.as_a.map(&.as_s)) || ["Geral"]
            tag = tags.first? || "Geral"
            tagged_operations[tag] ||= [] of Tuple(String, String, JSON::Any, Array(JSON::Any))
            tagged_operations[tag] << {http_verb.upcase, path_key, operation, path_params}
          end
        end

        tagged_operations.each do |tag_name, ops|
          io.puts "## #{tag_name}"
          io.puts ""

          ops.each do |verb, path_str, op, path_params|
            summary = op["summary"]?.try(&.as_s?) || ""
            desc = op["description"]?.try(&.as_s?) || ""
            has_auth = op["security"]?.nil? || (op["security"]?.try(&.as_a.size) || 0) > 0

            anchor = "#{verb.downcase}-#{path_str.gsub("/", "").gsub("{", "").gsub("}", "").gsub("_", "-")}"
            io.puts "<a id=\"#{anchor}\"></a>"
            io.puts "### `#{verb}` #{path_str}"
            io.puts ""
            io.puts "**#{summary}**"
            io.puts ""
            if !desc.empty? && desc != summary
              io.puts desc
              io.puts ""
            end
            io.puts "- **Autenticação:** #{has_auth ? "Bearer Token obrigatório" : "Pública (sem autenticação)"}"
            io.puts ""

            # Parameters
            op_params = op["parameters"]?.try(&.as_a) || [] of JSON::Any
            params = (path_params + op_params).uniq { |p| "#{p["name"]?.try(&.as_s?)}_#{p["in"]?.try(&.as_s?)}" }
            unless params.empty?
              io.puts "#### Parâmetros"
              io.puts ""
              io.puts "| Nome | Em | Tipo | Obrigatório | Descrição |"
              io.puts "|:---|:---|:---|:---:|:---|"
              params.each do |param|
                p_name = param["name"]?.try(&.as_s?) || ""
                p_in = param["in"]?.try(&.as_s?) || ""
                p_type = param.dig?("schema", "type").try(&.as_s?) || "string"
                p_req = param["required"]?.try(&.as_bool) ? "Sim" : "Não"
                p_desc = param["description"]?.try(&.as_s?) || "-"
                io.puts "| `#{p_name}` | `#{p_in}` | `#{p_type}` | #{p_req} | #{p_desc} |"
              end
              io.puts ""
            end

            # Request Body
            if req_body = op["requestBody"]?
              io.puts "#### Request Body"
              io.puts ""
              req_required = req_body["required"]?.try(&.as_bool) ? "Obrigatório" : "Opcional"
              io.puts "- **Status:** #{req_required}"
              io.puts "- **Content-Type:** `application/json`"
              io.puts ""

              # Look up schema if ref
              schema_ref = req_body.dig?("content", "application/json", "schema", "$ref").try(&.as_s?)
              schema_def = nil
              if schema_ref && schema_ref.starts_with?("#/components/schemas/")
                schema_name = schema_ref.split("/").last
                schema_def = spec.dig?("components", "schemas", schema_name)
              else
                schema_def = req_body.dig?("content", "application/json", "schema")
              end

              if schema_def && (props = schema_def["properties"]?.try(&.as_h))
                required_fields = schema_def["required"]?.try(&.as_a.map(&.as_s)) || [] of String

                io.puts "| Campo | Tipo | Obrigatório | Padrão | Descrição |"
                io.puts "|:---|:---|:---:|:---:|:---|"
                props.each do |f_name, f_def|
                  f_type = f_def["type"]?.try(&.as_s?) || "string"
                  f_req = required_fields.includes?(f_name) ? "Sim" : "Não"
                  f_default = f_def["default"]?.try(&.to_s) || "-"
                  f_desc = f_def["description"]?.try(&.as_s?) || "-"
                  io.puts "| `#{f_name}` | `#{f_type}` | #{f_req} | `#{f_default}` | #{f_desc} |"
                end
                io.puts ""
              end
            end

            # Example cURL
            io.puts "#### Exemplo de Requisição (cURL)"
            io.puts ""
            io.puts "```bash"
            curl_cmd = "curl -X #{verb} \"http://127.0.0.1:7443/api/v1#{path_str}\""
            if has_auth
              curl_cmd += " \\\n     -H \"Authorization: Bearer $WGCTL_TOKEN\""
            end
            if op["requestBody"]?
              curl_cmd += " \\\n     -H \"Content-Type: application/json\" \\\n     -d '{\n       \"name\": \"cliente-novo\",\n       \"ip\": \"auto\",\n       \"device\": \"laptop\"\n     }'"
            end
            io.puts curl_cmd
            io.puts "```"
            io.puts ""

            # Responses
            if responses = op["responses"]?.try(&.as_h)
              io.puts "#### Respostas"
              io.puts ""
              responses.each do |status_code, resp_def|
                resp_desc = resp_def["description"]?.try(&.as_s?) || ""
                io.puts "- **HTTP `#{status_code}`:** #{resp_desc}"
              end
              io.puts ""
            end

            io.puts "---"
            io.puts ""
          end
        end

        # ─── Schemas / Models ────────────────────────────────────────────────
        if schemas = spec.dig?("components", "schemas").try(&.as_h)
          io.puts "## Modelos de Dados (Schemas)"
          io.puts ""

          schemas.each do |schema_name, schema_info|
            next if schema_name == "Error" # Already covered in standard response
            io.puts "### Modelo: `#{schema_name}`"
            io.puts ""

            if props = schema_info["properties"]?.try(&.as_h)
              required_list = schema_info["required"]?.try(&.as_a.map(&.as_s)) || [] of String

              io.puts "| Propriedade | Tipo | Obrigatório | Exemplo / Descrição |"
              io.puts "|:---|:---|:---:|:---|"
              props.each do |p_name, p_spec|
                p_type = p_spec["type"]?.try(&.as_s?) || "object"
                p_req = required_list.includes?(p_name) ? "Sim" : "Não"
                p_example = p_spec["example"]?.try(&.to_s) || p_spec["description"]?.try(&.as_s?) || "-"
                io.puts "| `#{p_name}` | `#{p_type}` | #{p_req} | `#{p_example}` |"
              end
              io.puts ""
            end
          end
        end

        io.to_s
      end
    end
  end
end
