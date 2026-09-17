## O que mudou na v0.6.0

A versão **v0.6.0** consolida o **wgctl** como um produto **100% estável e pronto para ambientes de produção (Enterprise-Ready)**, trazendo uma auditoria aprofundada de segurança, hardening de parsers, suporte oficial a Docker com privilégio mínimo e documentação nativa em Markdown.

---

### Destaques da Versão

#### 1. Auditoria de Segurança e Hardening de Parsers
- **Mitigação contra INI / CRLF Injection**: Validação estrita de caracteres em nomes de peers (`^[a-zA-Z0-9_\-\.]{1,64}$`) com rejeição imediata de quebras de linha (`\r`, `\n`) em nomes, descrições e metadados. Sanitização defensiva adicional no formatador de comentários WireGuard.
- **Blindagem contra Path Traversal**: Validação rigorosa do identificador de interface (`^[a-zA-Z0-9_\-\.]{1,32}$`), impedindo qualquer manipulação de diretório (`/`, `\`, `..`) na resolução de arquivos de configuração.
- **Resistência a Timing Attacks**: Implementada comparação em tempo constante (`Crypto::Subtle.constant_time_compare`) na autenticação de tokens no daemon REST.
- **Robustez de Parsing e Rede**: Validação defensiva de octetos IPv4 em `IPAllocator` e garantia de descarte imediato de arquivos temporários de sincronização de kernel via bloco `ensure`.
- **Nova Suite de Testes de Segurança**: Adicionados testes dedicados em `spec/security_audit_spec.cr`, totalizando **52 specs passando com 0 falhas e 0 erros**.

#### 2. Suporte Oficial a Docker com Mínimo Privilégio
- **Segurança Máxima**: Container projetado para operar **sem** a flag `--privileged`, necessitando apenas da capability `CAP_NET_ADMIN` e `/dev/net/tun`.
- **Deploy Simplificado**: Arquivo `compose.yaml` moderno e leve (sem chave `version` legada) utilizando `network_mode: host` por padrão.
- **Auto-Inicialização Segura**: Inicialização automática opcional via variáveis de ambiente (`WGCTL_INIT=true`, `WGCTL_SERVER_IP`, `WGCTL_PORT`) e suporte a Docker Secrets para tokens de autenticação (`WGCTL_TOKEN_FILE`).
- **Guia Completo**: Documentação detalhada em `docs/docker.md` abordando tanto o modo host quanto o modo rede isolada.

#### 3. Gerador Nativo de Documentação OpenAPI Markdown
- Novos comandos `wgctl docs` e `wgctl daemon docs -o docs/api.md` para exportar a referência completa da API REST em formato Markdown profissional, contendo tabelas de parâmetros, schemas e exemplos de requisição/resposta.

---

### Instalação e Atualização

#### Linux (curl one-liner)
```bash
curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | bash
```

#### Windows (PowerShell one-liner)
```powershell
irm https://raw.githubusercontent.com/gmnds/wgctl/main/install.ps1 | iex
```

#### Docker
```bash
docker compose up -d
```

---

<details>
<summary><strong>English Description</strong></summary>

## What's Changed in v0.6.0

Release **v0.6.0** establishes **wgctl** as a fully stable, enterprise-ready WireGuard management suite, featuring comprehensive security hardening, parser resilience, least-privilege Docker support, and native OpenAPI Markdown generation.

### Key Highlights
- **Security & Parser Hardening**: Mitigated CRLF/INI injection in peer metadata comments; enforced strict regex validation against path traversal; implemented constant-time comparison (`Crypto::Subtle.constant_time_compare`) for bearer token authentication; fortified IP subnet parsing; and added guaranteed tempfile cleanup via `ensure`.
- **Least-Privilege Docker Integration**: Dockerfile and `compose.yaml` operating with minimal capabilities (`CAP_NET_ADMIN` without `--privileged`), host networking by default, automated server init via env vars, and Docker secret support (`WGCTL_TOKEN_FILE`).
- **OpenAPI Markdown Generator**: Native CLI generator (`wgctl docs` / `wgctl daemon docs`) creating publication-ready API documentation in Markdown.
- **Test Suite**: 52 automated specifications with 100% pass rate.

</details>

---

**Full Changelog**: https://github.com/GMNDS/wgctl/compare/v0.5.2...v0.6.0
