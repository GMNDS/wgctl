## O que mudou na v0.6.1

A versão **v0.6.1** traz correções críticas para peers com chaves pré-compartilhadas (PSK), suporte completo a **AllowedIPs** customizáveis com pré-definições (`all`, `vpn`), além de aprimoramentos adicionais de segurança e usabilidade na CLI e API REST.

---

### Destaques da Versão

#### 1. Correção Crítica: Inclusão de `PresharedKey` na Configuração do Cliente
- **Problema Corrigido**: Quando um peer era registrado com a flag `--preshared-key`, a chave Curve25519 gerada era gravada corretamente na configuração do servidor (`wg0.conf`), mas a linha `PresharedKey = ...` era omitida na geração do `.conf` do cliente e no QR code via `wgctl client <name>`, impedindo a conclusão do handshake WireGuard.
- **Correção**: `wgctl client`, o assistente interativo (`wgctl menu`) e os endpoints da API REST (`/api/v1/interfaces/:name/peers/:key/config` e `/qr`) agora incluem automaticamente a `PresharedKey` no bloco `[Peer]` quando ela está associada ao cliente.
- **Suporte a Rotação de PSK**: Adicionado suporte para adicionar ou rotacionar a PSK de um peer existente com `wgctl peer edit <name> --preshared-key`.

#### 2. AllowedIPs Personalizáveis com Pré-definições (`all`, `vpn`)
- **Pré-definição `all` (Full-Tunnel)**: Gera `AllowedIPs = 0.0.0.0/0, ::/0` (padrão), direcionando todo o tráfego do cliente através da VPN.
- **Pré-definição `vpn` (Split-Tunnel)**: Calcula automaticamente a sub-rede da interface WireGuard (ex: `10.13.14.0/24`), garantindo que apenas o tráfego da rede privada passe pela VPN enquanto a navegação de internet comum segue direto pelo provedor local.
- **Rotas Customizadas**: Permite fornecer listas personalizadas de CIDRs separados por vírgula (ex: `--allowed-ips "10.13.14.0/24, 192.168.10.0/24"`).
- **Persistência em Metadados**: A preferência de roteamento do peer pode ser gravada na criação (`wgctl peer add <name> --allowed-ips vpn`) ou edição (`wgctl peer edit <name> --allowed-ips ...`), persistida em `# wgctl:client_allowed_ips=...` e refletida automaticamente em `wgctl client <name>`.
- **Assistente Interativo**: O comando `wgctl menu` agora oferece a escolha direta do modo de roteamento (Toda a internet, Apenas VPN ou Personalizado) ao registrar novos dispositivos.
- **API REST**: Query parameter `?allowed_ips=<all|vpn|CIDRs>` disponível nas rotas de configuração e QR code para sobrescrita dinâmica, além de suporte nos payloads de adição e edição de peers.

#### 3. Hardening de Segurança e Zero-Knowledge Keys
- **Chaves Privadas Zero-Knowledge**: A chave privada do cliente não é gravada no arquivo de configuração do servidor em comentários de metadados. Ela é exibida uma única vez no momento da criação.
- **Rotação de Chaves via CLI**: Novo comando `wgctl client <name> --rotate` para gerar um novo par de chaves, atualizar a chave pública no servidor e aplicar as alterações ao vivo sem interrupção dos demais túneis.
- **Sanitização de Interface WAN**: Validação defensiva de identificadores de interface WAN em `FirewallManager` para proteger regras `PostUp` e `PostDown` contra injeção de comandos de shell.
- **Proteção de Token de Autenticação**: Tokens REST via query parameter foram restritos estritamente ao handshake WebSocket em `/live`, prevenindo vazamento de credenciais em logs de acesso HTTP.

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

## What's Changed in v0.6.1

Version **v0.6.1** addresses critical bug fixes for Curve25519 Pre-shared Keys (PSK), introduces comprehensive client **AllowedIPs** customization with presets (`all`, `vpn`), and includes further security hardening across the CLI and REST API daemon.

### Highlights
- **PresharedKey Bugfix**: Ensures `PresharedKey = ...` is properly rendered in generated client configurations (`wgctl client`) and REST API responses when enabled on a peer.
- **Custom AllowedIPs with Presets**: Flexible client routing with presets for full-tunnel (`all` -> `0.0.0.0/0, ::/0`), split-tunnel (`vpn` -> dynamically calculated interface subnet, e.g. `10.13.14.0/24`), or custom CIDR lists across CLI, metadata, TUI menu, and API.
- **Security Hardening**: Zero-knowledge client private keys, key rotation via `wgctl client <name> --rotate`, WAN interface sanitization in firewall hooks, and query token restriction on HTTP endpoints.

</details>
