## O que mudou na v0.6.3

A versão **v0.6.3** corrige a falha `Warning: wg syncconf failed: fopen: Permission denied` ocorrida ao sincronizar alterações de peers em tempo real em distribuições Linux (como Ubuntu e Debian) que utilizam perfis restritivos do AppArmor para o utilitário `/usr/bin/wg`.

---

### Destaques da Versão

#### Correção: Resolução de `fopen: Permission denied` com AppArmor
- **Causa Raiz**: O utilitário `wg syncconf` executa a chamada C `fopen()` para ler o arquivo de configuração limpo gerado temporariamente. Nas distribuições modernas (Ubuntu 23+, Debian), o perfil padrão do AppArmor para `/usr/bin/wg` restringe a leitura de arquivos exclusivamente ao diretório `/etc/wireguard/**`. Ao criar arquivos temporários em `/tmp` (comportamento padrão de `File.tempfile`), o AppArmor bloqueava a leitura pelo binário `wg` com `EACCES` (`fopen: Permission denied`), inclusive quando executado como `root` via `sudo`.
- **Solução Implementada**:
  1. O arquivo temporário limpo gerado para sincronização em tempo real agora é criado diretamente dentro do diretório de configuração do WireGuard (ex.: `/etc/wireguard/.wgctl-sync-wg0-<pid>-<hash>.conf`) quando este for gravável, herdando as permissões liberadas pelo perfil AppArmor (`/etc/wireguard/** r,`) com permissões estritas `0600`.
  2. Fallback gracioso para o diretório temporário do sistema (`/tmp`) caso o diretório de configuração não possua permissão de escrita.
  3. Limpeza garantida do arquivo temporário no bloco `ensure`, assegurando que nenhum arquivo residual permaneça em `/etc/wireguard`.
  4. Mensagens de erro contextualizadas: caso o AppArmor ainda bloqueie a chamada por regras customizadas na máquina do usuário, a mensagem de aviso agora instrui diretamente a verificação via `sudo dmesg | grep -i apparmor` ou execução do modo de reclamação com `sudo aa-complain /etc/apparmor.d/wg`.

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

## What's Changed in v0.6.3

Version **v0.6.3** fixes the `Warning: wg syncconf failed: fopen: Permission denied` issue when applying live peer synchronization on Linux distributions (such as Ubuntu and Debian) with restrictive AppArmor profiles enabled for `/usr/bin/wg`.

### Highlights
- **AppArmor Compatibility for `wg syncconf`**: Writes the temporary stripped WireGuard configuration file directly inside `/etc/wireguard/` (e.g. `/etc/wireguard/.wgctl-sync-wg0-...conf`) with `0600` permissions. This satisfies Ubuntu's default AppArmor policy restricting `wg` reads to `/etc/wireguard/**`.
- **Graceful Fallback**: Automatically falls back to system temporary directory (`/tmp`) if the configuration directory is not writable.
- **Guaranteed Cleanup**: Immediately deletes the temporary file in an `ensure` block.
- **Actionable Error Diagnostics**: Provides helpful troubleshooting guidance if AppArmor confinement continues to block system utilities.

</details>
