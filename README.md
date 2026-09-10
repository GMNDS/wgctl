# wgctl

CLI simples, rápida e amigável para administrar e visualizar interfaces WireGuard de forma muito mais legível que `wg` e `wg-quick`.

O `wgctl` atua como uma camada segura e intuitiva sobre:
* `/etc/wireguard/*.conf`
* `wg`
* `wg-quick`
* `systemctl`

---

## Principais Objetivos

* **Identificação clara de peers**: Associar nomes, descrições e tipo de dispositivo a cada chave pública.
* **Status amigável**: Visão rápida de quem está online, transferências (RX/TX formatados em KB/MB/GB), último handshake e IP.
* **100% Compatível com WireGuard**: Usa metadados em comentários (`# wgctl:*`) no próprio `.conf` sem quebrar `wg-quick` ou ferramentas existentes.
* **Gerenciamento Seguro e Atômico**:
  * Backups automáticos antes de cada modificação (`backups/wg0.conf.YYYY-MM-DDTHHMMSS`).
  * Gravação atômica via arquivo temporário.
  * Permissões restritas (`0600`) para arquivos que contêm chaves privadas.
  * Nunca exibe chaves privadas em comandos de consulta (`status`, `peers`, `peer show`).
* **Automação e Integração**: Suporte a `--json` em todos os comandos de consulta e alocação automática de IP (`--ip auto`).
* **Configuração de Clientes e QR Code**: Geração imediata de arquivo `.conf` para clientes e QR Code no terminal (`--qr`) para dispositivos móveis.
* **Recarregamento sem Downtime**: Aplicação de alterações via `wg syncconf` sem derrubar túneis ativos.

---

## Instalação Rápida (1 Comando)

### Linux e macOS (One-liner)
Para instalar ou atualizar automaticamente com detecção de arquitetura (x86_64 / ARM64):

```bash
curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | bash
```

> **Dica:** Para instalar uma versão específica:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | VERSION=v0.1.0 bash
> ```

### Windows (Nativo)
Baixe o executável `wgctl-windows-amd64.exe` da página de [Releases](https://github.com/gmnds/wgctl/releases), renomeie para `wgctl.exe` e adicione ao seu `PATH`.

---

## Compilação Manual

### Pré-requisitos (Debian / Ubuntu / Linux)
```bash
sudo apt update
sudo apt install -y crystal shards wireguard-tools qrencode make
```

### Comandos de Compilação
```bash
# Binário dinâmico local
make build

# Binário otimizado release
make release

# Binário ESTÁTICO (roda em qualquer Linux sem dependências de glibc)
make static

# Executar testes unitários e de integração
make test

# Instalar no sistema (/usr/local/bin)
sudo make install
```

---

## Uso e Exemplos

### 1. Status Geral da Interface e Peers
```bash
wgctl status
# ou especificando a interface:
wgctl status wg0
# ou especificando arquivo de configuração direto:
wgctl --config ./wg0.conf status
```

Exemplo de saída:
```text
Interface: wg0
Address: 10.13.14.1/24
Listen Port: 51823

NAME        IP            ENDPOINT               HANDSHAKE    RX       TX
asteri-c    10.13.14.9    1.2.3.4:32910          12s ago      82 MB    31 MB
pc          10.13.14.2    177.x.x.x:51820        1m ago       2 GB     800 MB
mobile      10.13.14.3    200.x.x.x:51123        offline      0 B      0 B
```

### 2. Listar Interfaces
```bash
wgctl interfaces
```

### 3. Listar Peers
```bash
wgctl peers
wgctl peers wg0
```
```text
NAME        ADDRESS        PUBLIC KEY
asteri-c    10.13.14.9     Aste...56=
pc          10.13.14.2     PcPu...12=
mobile      10.13.14.3     Mobi...78=
```

### 4. Detalhes de um Peer
Pode ser consultado por nome ou por chave pública:
```bash
wgctl peer asteri-c
# ou
wgctl peer show asteri-c
# ou pela chave pública:
wgctl peer AsteriCPublicKey...
```
```text
Name:         asteri-c
Description:  Contabo Germany
Device:       server
Public Key:   AsteriCPublicKeyBase64StringForTesting123456=
Allowed IPs:  10.13.14.9/32
Endpoint:     1.2.3.4:32910
Handshake:    12s ago
Received:     82 MB
Sent:         31 MB
```

### 5. Adicionar Peer
Com IP específico:
```bash
wgctl peer add asteri-c --ip 10.13.14.9
```
Com alocação automática de IP (procura o primeiro `/32` livre na subnet da interface):
```bash
wgctl peer add mobile \
  --ip auto \
  --description "Meu celular" \
  --device mobile
```
Suporta simulação com `--dry-run`:
```bash
wgctl peer add mobile --ip auto --dry-run
```

### 6. Editar Peer
```bash
wgctl peer edit mobile --description "Novo Smartphone" --device android
```

### 7. Remover Peer
```bash
# Simulação
wgctl peer remove mobile --dry-run

# Remoção real com backup e recarregamento seguro
wgctl peer remove mobile
```

### 8. Gerar Configuração de Cliente e QR Code
Exibir configuração no terminal:
```bash
wgctl client mobile
```

Salvar diretamente em arquivo com permissões `0600`:
```bash
wgctl client mobile --output mobile.conf
```

Exibir QR Code diretamente no terminal para escanear no celular (iOS/Android):
```bash
wgctl client mobile --qr
```

### 9. Validação e Diagnóstico de Configuração
Detecta chaves públicas duplicadas, IPs em conflito, nomes duplicados e peers sem metadados:
```bash
wgctl check
wgctl check wg0
```
```text
✓ interface wg0
✓ 3 peers
✓ no duplicate addresses
```

### 10. Aplicar Alterações ao Vivo (Sem Downtime)
```bash
wgctl apply wg0
```
Utiliza `wg syncconf` para sincronizar os peers com o kernel Linux sem reiniciar a interface ou interromper o tráfego dos demais peers.

### 11. Saída em JSON
Disponível em todos os comandos de consulta:
```bash
wgctl status --json
wgctl interfaces --json
wgctl peers --json
wgctl peer show asteri-c --json
wgctl check --json
```

---

## Formato dos Metadados

O `wgctl` armazena as informações adicionais dos peers diretamente no arquivo `.conf` como comentários padrão:

```ini
# wgctl:name=asteri-c
# wgctl:description=Contabo Germany
# wgctl:device=server
# wgctl:client_private_key=...
[Peer]
PublicKey = AsteriCPublicKey...
AllowedIPs = 10.13.14.9/32
```

O WireGuard ignora essas linhas, garantindo compatibilidade total com `wg-quick` e ferramentas nativas.

---

## Arquitetura do Projeto

```text
src/
├── wgctl.cr               # Ponto de entrada
├── cli/
│   ├── context.cr         # Contexto, flags e descoberta automática de interfaces
│   └── dispatcher.cr      # Roteamento e parsing de subcomandos e opções
├── models/
│   ├── metadata.cr        # Metadados de peer (name, description, device)
│   ├── runtime_peer.cr    # Dados dinâmicos do kernel (dump wg)
│   ├── peer.cr            # Modelo completo de Peer (config + runtime)
│   └── interface.cr       # Modelo de Interface
├── metadata/
│   ├── parser.cr          # Leitor de comentários # wgctl:*
│   └── formatter.cr       # Formatador de comentários
├── config/
│   ├── parser.cr          # Parser não destrutivo de .conf
│   ├── writer.cr          # Gravador atômico com backup e permissões 0600
│   ├── ip_allocator.cr    # Alocador automático de IPs livres /32
│   └── validator.cr       # Validador de consistência e integridade
├── wireguard/
│   ├── runner.cr          # Integração com wg, wg-quick, qrencode
│   ├── dump_parser.cr     # Parser de saída tabular wg show dump
│   └── keys.cr            # Geração de chaves WireGuard Curve25519
├── commands/              # Implementação de cada comando CLI
└── output/
    ├── table.cr           # Renderizador ASCII tabular
    ├── formatter.cr       # Formatação humana de status, peers e relatórios
    └── json_formatter.cr  # Serialização JSON estruturada
```

---

## Testes

A suíte de testes unitários e de integração pode ser executada com:
```bash
crystal spec
```
