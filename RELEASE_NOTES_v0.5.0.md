## Novidades na v0.5.0

O `wgctl v0.5.0` introduz o **Remote Client** (`wgctl remote` / `wgctl attach`), permitindo gerenciar servidores WireGuard remotamente direto do seu computador local (macOS, Windows ou Linux) sem precisar de permissões de root ou WireGuard instalado localmente.

---

### Funcionalidades
* **Cliente Remoto (`wgctl remote` / `wgctl attach`)**:
  - `wgctl remote connect <url> --token <token>` (ou `wgctl attach <url> --token <token>`): Conecta ao daemon remoto e salva como perfil ativo.
  - `wgctl remote list`: Lista todos os perfis de servidores remotos salvos.
  - `wgctl remote use <perfil>`: Alterna entre múltiplos servidores (ex: `prod`, `homelab`).
  - `wgctl remote status`: Mede a latência em tempo real e verifica a saúde do servidor remoto.
  - `wgctl remote disconnect`: Encerra a conexão remota ativa e retorna ao modo local.
* **Execução Transparente via CLI**:
  - `wgctl status`, `wgctl peers`, `wgctl peer add`, `wgctl peer edit`, `wgctl peer remove`, `wgctl client` e `wgctl menu` passam a se comunicar diretamente via REST API HTTPS com o servidor remoto.
* **Flags Remotas Ad-Hoc**: Permite rodar comandos isolados contra qualquer servidor sem alterar o perfil salvo:
  - `wgctl status --remote https://vpn.exemplo.com:7443 --token <token>`
* **Armazenamento Seguro de Perfis**: Credenciais e tokens Bearer são guardados em `~/.config/wgctl/remote.json` com permissão estrita `0600`.
* **Indicador Remoto no Menu Interativo**: O assistente TUI (`wgctl menu`) exibe `[REMOTO: <url>]` no cabeçalho quando conectado.

---

### Instalação e Atualização

```bash
curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | bash
```

---

<details>
<summary><strong>English Description</strong></summary>

## What's New in v0.5.0

`wgctl v0.5.0` introduces the **Remote Client**, allowing administrators to manage WireGuard servers remotely from their local machines (macOS, Windows, Linux) without needing root access or WireGuard installed locally.

### Features
* **Remote Client (`wgctl remote` / `wgctl attach`)**:
  - `wgctl remote connect <url> --token <token>`: Connect to a remote daemon and save it as an active profile.
  - `wgctl remote list`: View all configured remote server profiles.
  - `wgctl remote use <profile>`: Switch between multiple remote servers.
  - `wgctl remote status`: Measure real-time roundtrip latency and server health.
  - `wgctl remote disconnect`: Safely clear active remote session and return to local mode.
* **Transparent CLI Execution**:
  - All standard commands (`status`, `peers`, `peer add`, `peer edit`, `peer remove`, `client`, `menu`) seamlessly communicate over HTTPS REST with the remote server.
* **Ad-Hoc Remote Flags**: Run one-off commands against any remote daemon via `--remote` and `--token`.
* **Secure Profile Storage**: Stored in `~/.config/wgctl/remote.json` with strict `0600` permissions.

</details>

---

**Full Changelog**: https://github.com/GMNDS/wgctl/compare/v0.4.10...v0.5.0
