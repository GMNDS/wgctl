# Notas da Versão v0.5.2 / Release Notes v0.5.2

## Português (Principal)

### Estabilidade e Correção de Bugs Críticos

A versão **v0.5.2** consolida a estabilidade do `wgctl`, trazendo correções em comunicação remota, concorrência, consumo de memória e resiliência de rede.

---

### Principais Alterações e Correções

#### 1. Suporte a Modo Remoto nos Comandos `apply` e `interfaces`
- **`wgctl apply`**: Agora detecta conexões remotas ativas e despacha a requisição de aplicação no kernel diretamente para a API REST do daemon remoto (`/api/v1/interfaces/:name/apply`), em vez de tentar ler arquivos locais do sistema cliente.
- **`wgctl interfaces`**: Quando conectado a um servidor remoto, lista as interfaces gerenciadas pelo servidor remoto ao invés de ler apenas o filesystem local.

#### 2. Timeouts de Rede e Fechamento Seguro de Sockets (`ApiClient`)
- Adicionados timeouts explícitos de conexão (`connect_timeout = 5s`) e de leitura (`read_timeout = 15s`) no cliente HTTP.
- Garantido o encerramento do socket TCP através de bloco `ensure client.close`, evitando esgotamento de descritores de arquivo em execuções contínuas.

#### 3. Otimização do Alocador de IPs contra Esgotamento de Memória (`IPAllocator`)
- Substituída a materialização e ordenação em memória de arrays de candidatos por uma busca sequencial circular em stream com complexidade de memória O(1).
- Subnets grandes como `/16` (65.534 IPs) e `/8` (16,7 milhões de IPs) agora alocam o próximo IP livre instantaneamente sem consumo excessivo de memória RAM ou risco de Out-of-Memory.

#### 4. Sincronização de Concorrência e Debounce de Disco
- **`ApiRouter`**: Adicionado `Mutex` de exclusão mútua em rotas de mutação de interfaces e peers (`POST /peers`, `PATCH /peers/:key`, `DELETE /peers/:key`, `POST /apply`), eliminando race conditions sob requisições paralelas.
- **`TokenStore`**: Protegido o acesso e modificação da lista de tokens com `Mutex`. Adicionado debounce na gravação em disco do registro de uso (`last_used_at`), evitando sobrecarga desnecessária de I/O em alta frequência de requisições autenticadas.

#### 5. Experiência de Usuário e Terminal (TUI)
- Removidos emojis e caracteres inconsistentes das telas interativas.
- No menu interativo (`wgctl menu`), as opções de manipulação exclusiva de filesystem local (`migrate` e `init`) agora são claramente sinalizadas com aviso amigável quando em modo remoto.

---

## English (Secondary)

### Stability & Critical Bug Fixes

Version **v0.5.2** consolidates the stability of `wgctl`, bringing fixes for remote communication, concurrency, memory footprint, and network resilience.

#### Key Changes:
- **Remote Client Support in `apply` & `interfaces`**: Transparently dispatches kernel sync and interface listing to the remote daemon instead of querying local files.
- **Network Timeouts & Socket Cleanup**: Configured connection and read timeouts on `ApiClient` with guaranteed socket closure.
- **O(1) Memory Footprint in IP Allocator**: Circular sequential stream search avoids array materialization in large `/16` or `/8` subnets.
- **Concurrency & Mutex Synchronization**: Thread/Fiber-safe mutations in `ApiRouter` and disk debounce for token usage persistence in `TokenStore`.
- **Clean Terminal UI**: Removed all emojis and provided clear notices for local-only actions in remote mode.
