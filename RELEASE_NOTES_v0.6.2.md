## O que mudou na v0.6.2

A versão **v0.6.2** resolve uma regressão crítica na geração de QR Codes para clientes WireGuard, garantindo que chaves privadas válidas de 32 bytes (base64) sejam sempre fornecidas para o app WireGuard em dispositivos móveis e desktops.

---

### Destaques da Versão

#### Correção Crítica: Chave Privada em QR Codes e Metadados
- **Problema Corrigido**: Em versões anteriores, o metadado do peer no servidor não persistia a chave privada do cliente (`# wgctl:client_private_key=...`), fazendo com que o comando `wgctl client <name> --qr` gerasse uma configuração contendo o texto literal `PrivateKey = <REPLACE_WITH_CLIENT_PRIVATE_KEY>`. Ao escanear esse QR Code no aplicativo WireGuard (Android/iOS), o aplicativo rejeitava a importação informando que a chave privada possuía tamanho incorreto (deve ter exatamente 32 bytes).
- **Correção**:
  1. A chave privada do cliente gerada para o peer passa a ser persistida em `# wgctl:client_private_key=...` no arquivo de configuração do servidor (`wg0.conf` em modo restrito 0600), permitindo que `wgctl client <name> --qr`, o menu interativo e a API REST exibam QR codes funcionais a qualquer momento.
  2. Auto-recuperação transparente: caso um peer antigo tenha sido criado sem a chave privada salva, o comando `wgctl client <name> --qr` agora gera automaticamente um novo par de chaves Curve25519 válido, atualiza o servidor e renderiza o QR code funcional imediatamente.
  3. Tratamento robusto contra ausência do binário `qrencode`, exibindo a configuração em texto com mensagem explicativa em vez de abortar o processo.

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

## What's Changed in v0.6.2

Version **v0.6.2** fixes a critical bug where QR codes generated for WireGuard clients contained a placeholder `<REPLACE_WITH_CLIENT_PRIVATE_KEY>` instead of a valid 32-byte base64 Curve25519 private key, causing official WireGuard mobile apps to fail with an incorrect key length error upon import.

### Highlights
- **Client Private Key Persistence**: Saves `# wgctl:client_private_key=...` in server configuration comments (mode 0600) so `wgctl client <name> --qr`, TUI menu, and REST API always render scannable QR codes.
- **Transparent Auto-Rotation**: If an existing peer lacks a stored private key, requesting `--qr` automatically provisions a fresh keypair and syncs the server live so the rendered QR code is immediately valid.
- **Graceful QR Fallback**: Fallbacks cleanly when `qrencode` is not installed on the host system.

</details>
