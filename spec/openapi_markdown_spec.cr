require "./spec_helper"
require "../src/server/openapi"
require "../src/server/openapi_markdown"
require "../src/commands/daemon_command"

describe Wgctl::Server::OpenAPIMarkdown do
  it "generates complete and structured markdown from OpenAPI spec" do
    markdown = Wgctl::Server::OpenAPIMarkdown.generate
    markdown.should_not be_empty

    # Verifica seções essenciais
    markdown.should contain("# wgctl REST API (v#{Wgctl::Commands::VersionCommand::VERSION})")
    markdown.should contain("## Autenticação")
    markdown.should contain("## Formato de Resposta Padrão")
    markdown.should contain("## Índice de Endpoints")
    markdown.should contain("## Health")
    markdown.should contain("## Interfaces")
    markdown.should contain("## Peers")
    markdown.should contain("## Modelos de Dados (Schemas)")

    # Verifica rotas
    markdown.should contain("`GET` /health")
    markdown.should contain("`GET` /interfaces")
    markdown.should contain("`POST` /interfaces/{name}/apply")
    markdown.should contain("`POST` /interfaces/{name}/peers")
    markdown.should contain("`PATCH` /interfaces/{name}/peers/{key}")
    markdown.should contain("`DELETE` /interfaces/{name}/peers/{key}")
    markdown.should contain("`GET` /interfaces/{name}/peers/{key}/config")
    markdown.should contain("`GET` /interfaces/{name}/peers/{key}/qr")

    # Verifica blocos de cURL
    markdown.should contain("curl -X GET")
    markdown.should contain("curl -X POST")
    markdown.should contain("Authorization: Bearer $WGCTL_TOKEN")
  end

  it "writes markdown to output file correctly" do
    temp_md = File.tempfile("api_doc_test", ".md").path
    File.delete(temp_md) rescue nil

    ctx = Wgctl::CLI::Context.new
    Wgctl::Commands::DaemonCommand.run_docs(ctx, ["--output", temp_md])

    File.exists?(temp_md).should be_true
    content = File.read(temp_md)
    content.should contain("# wgctl REST API")
    content.should contain("## Índice de Endpoints")

    File.delete(temp_md) rescue nil
  end

  it "exports raw JSON when format is json" do
    temp_json = File.tempfile("api_spec_test", ".json").path
    File.delete(temp_json) rescue nil

    ctx = Wgctl::CLI::Context.new
    Wgctl::Commands::DaemonCommand.run_docs(ctx, ["--json", "-o", temp_json])

    File.exists?(temp_json).should be_true
    raw = File.read(temp_json)
    parsed = JSON.parse(raw)
    parsed["openapi"].as_s.should eq("3.0.3")
    parsed["info"]["title"].as_s.should eq("wgctl REST API")

    File.delete(temp_json) rescue nil
  end
end
