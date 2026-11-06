## O que mudou na v0.5.1

Esta versão traz uma correção importante para o encaminhamento de subcomandos durante a auto-elevação via `sudo`.

---

### Correções
* **Correção no Encaminhamento de Argumentos com `sudo`**:
  - Corrigido um problema onde a execução de subcomandos sem permissão de root (ex: `wgctl peer edit <nome> ...` ou `wgctl peer add ...`) fazia o parser consumir argumentos posicionais antes do `sudo`, resultando no erro incorreto `Error: Unknown command: '<nome>'`.
  - O CLI agora preserva uma cópia intacta de todos os argumentos originais (`original_argv`) antes do processamento de opções, garantindo que o comando seja reexecutado de forma idêntica e transparente com privilégios elevados.

---

### Instalação e Atualização

```bash
curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | bash
```

---

<details>
<summary><strong>English Description</strong></summary>

## What's Changed in v0.5.1

This release brings a critical fix for subcommand auto-elevation with `sudo`.

### Bug Fixes
* **Fix `sudo` Auto-Elevation Argument Truncation**:
  - Fixed an issue where executing subcommands without root permissions (e.g. `wgctl peer edit <name> ...` or `wgctl peer add ...`) caused `OptionParser` to consume positional words, leading to `Error: Unknown command: '<name>'`.
  - The CLI now preserves a clean copy of the original invocation arguments (`original_argv`) before option parsing, ensuring transparent and accurate re-execution via `sudo`.

</details>

---

**Full Changelog**: https://github.com/GMNDS/wgctl/compare/v0.5.0...v0.5.1
