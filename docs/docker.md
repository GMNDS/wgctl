# Guia de Conteinerização com Docker e Mínimo Privilégio

Este guia detalha a execução do **wgctl** e do WireGuard em containers Docker, cobrindo o modelo de segurança com menor privilégio possível, arquiteturas de rede (Modo Host vs Modo Bridge), auto-inicialização segura e gestão de segredos.

---

## 1. Princípio do Menor Privilégio (Least Privilege)

A maioria dos tutoriais de WireGuard em Docker sugere utilizar a flag `privileged: true`. Essa abordagem é **perigosa e desnecessária**, pois desativa os perfis de segurança do Seccomp/AppArmor, remove o isolamento de dispositivos físicos e concede acesso irrestrito ao host.

### O que o WireGuard realmente precisa:
- **`CAP_NET_ADMIN`**: Necessário para criar interfaces virtuais WireGuard, atribuir endereços IP e manipular a tabela de rotas.
- **`CAP_NET_RAW`**: Necessário para manipular regras de firewall (`iptables` / `ip6tables`) no roteamento de pacotes (NAT/MASQUERADE).
- **`cap_drop: [ALL]`**: Remove todas as outras capacidades desnecessárias do Linux (como acesso a módulos do kernel, raw disk I/O, etc.).
- **`security_opt: [no-new-privileges:true]`**: Impede que qualquer processo dentro do container ganhe privilégios adicionais via `setuid` ou `setgid`.

> **Requisito no Host Linux (apenas 1 vez antes de iniciar):**
> O módulo do WireGuard deve estar carregado no kernel do host:
> ```bash
> sudo modprobe wireguard
> sudo sysctl -w net.ipv4.ip_forward=1
> ```

---

## 2. Arquiteturas de Rede

### Modo 1: Modo Host (`network_mode: host`) [Padrão e Recomendado]

No Modo Host, o container compartilha a stack de rede do host. A interface `wg0` e o IP `10.13.14.1` são criados diretamente no kernel do sistema.

#### Vantagens:
1. **Acesso direto aos serviços do host**: Qualquer serviço escutando no host em `10.13.14.1:porta` ou `0.0.0.0` (SSH, bancos de dados, outros containers) é acessível instantaneamente pelos clientes conectados na VPN.
2. **Suporte nativo a Site-to-Site (LAN-to-LAN)**: As rotas para as subnets remotas (ex: `192.168.10.0/24 dev wg0`) são injetadas diretamente na tabela de rotas do kernel do host (`ip route`). O host e qualquer máquina da rede local conseguem conversar com a ponta remota sem precisar de rotas manuais ou NAT duplo.
3. **Desempenho máximo**: Sem qualquer sobrecarga de processamento de pontes de rede virtuais (`docker0`).

#### Arquitetura Modo Host:
```
Internet 
   │
   ├─► UDP 51820 ──────► [ Host Linux: Interface wg0 (10.13.14.1/24) ]
   │                     │  • Conecta clientes VPN
   │                     │  • Roteia subnets remotas Site-to-Site (192.168.10.0/24)
   │                     │  • Acessa serviços do Host diretamente (10.13.14.1:porta)
   │                     │
   └─► TCP 7443 ─────────┴─► [ Container wgctl daemon ] (REST API & Web)
```

---

### Modo 2: Modo Bridge (Totalmente Isolado)

Neste modelo, o container roda em um namespace de rede isolado (`bridge`), expondo apenas portas mapeadas.

#### Quando usar:
- Quando você possui múltiplos servidores WireGuard concorrentes na mesma máquina física e quer isolamento absoluto entre eles.
- Ambientes onde o uso de `network_mode: host` é proibido por políticas organizacionais.

#### Limitações e Soluções no Modo Bridge:
- O IP `10.13.14.1` pertence **apenas ao container**. Para acessar serviços do host a partir da VPN:
  - Ou os clientes acessam pelo IP do gateway Docker (geralmente `172.17.0.1:porta`).
  - Ou adiciona-se uma regra DNAT no `PostUp` do `wg0.conf`:
    ```ini
    PostUp = iptables -t nat -A PREROUTING -d 10.13.14.1 -j DNAT --to-destination 172.17.0.1
    ```

#### Exemplo de `compose.yaml` em Modo Bridge:
```yaml
services:
  wgctl:
    build: .
    image: ghcr.io/gmnds/wgctl:latest
    container_name: wgctl
    restart: unless-stopped

    # Namespace isolado (Bridge padrão):
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - NET_RAW
    security_opt:
      - no-new-privileges:true

    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1

    ports:
      - "51820:51820/udp"
      - "7443:7443/tcp"

    volumes:
      - ./data/wireguard:/etc/wireguard
      - ./data/config:/root/.config/wgctl

    environment:
      - WGCTL_AUTO_INIT=true
      - WGCTL_TOKEN=wgctl_tok_seu_token_secreto_aqui
```

---

## 3. Auto-Init Seguro e Parametrização por ENVs

O `docker-entrypoint.sh` possui uma **blindagem de segurança contra sobrescrita**:

1. **Volume com configurações pré-existentes**: Se qualquer arquivo `.conf` for encontrado em `/etc/wireguard`, o entrypoint **ignora completamente a rotina de inicialização**. Nenhuma chave, IP ou arquivo é tocado ou sobrescrito. As interfaces existentes são apenas levantadas (`wg-quick up`).
2. **Volume novo / vazio**: Se a pasta estiver vazia e `WGCTL_AUTO_INIT=true` (padrão), ele executa `wgctl init` utilizando os parâmetros definidos nas variáveis de ambiente.

### Variáveis de Ambiente Suportadas:

| Variável | Padrão | Descrição |
|:---|:---|:---|
| **`WGCTL_AUTO_INIT`** | `true` | Executa inicialização automática se o volume `/etc/wireguard` estiver vazio |
| **`WGCTL_INTERFACE`** | `wg0` | Nome da interface WireGuard principal |
| **`WGCTL_SUBNET`** | `10.13.14.1/24` | IP interno do servidor e máscara da rede VPN |
| **`WGCTL_PORT`** | `51820` | Porta UDP de escuta do WireGuard |
| **`WGCTL_PUBLIC_IP`** | `auto` | IP público ou hostname DDNS para conexão dos clientes |
| **`WGCTL_DNS`** | `1.1.1.1, 1.0.0.1` | Servidores DNS que serão configurados nos clientes gerados |
| **`WGCTL_WAN`** | *auto* | Interface externa de internet para regras de NAT (ex: `eth0`, `ens3`) |
| **`WGCTL_FIRST_CLIENT`** | *vazio* | Nome opcional de um peer inicial para ser criado pronto (ex: `admin`) |
| **`WGCTL_NO_FIREWALL`** | `false` | Se `true`, não injeta regras de NAT PostUp/PostDown no `.conf` |
| **`WGCTL_TOKEN`** | *vazio* | Token Bearer da API REST configurado diretamente via variável |
| **`WGCTL_TOKEN_FILE`** | *vazio* | Caminho para arquivo de segredo Docker Secret (ex: `/run/secrets/wgctl_token`) |

---

## 4. Gestão de Segredos e Autenticação

Para conectar seu CLI local (`wgctl remote connect`) ao container sem precisar rodar comandos manuais no servidor, você pode definir o token antecipadamente:

### Opção A: Via Docker Secrets (Mais seguro)
Crie um arquivo local com o token:
```bash
echo "wgctl_tok_meu_token_super_secreto_123" > ./wgctl_token.txt
chmod 600 ./wgctl_token.txt
```

No `compose.yaml`:
```yaml
services:
  wgctl:
    # ...
    secrets:
      - wgctl_token
    environment:
      - WGCTL_TOKEN_FILE=/run/secrets/wgctl_token

secrets:
  wgctl_token:
    file: ./wgctl_token.txt
```

### Opção B: Via Variável de Ambiente Direta
```yaml
environment:
  - WGCTL_TOKEN=wgctl_tok_meu_token_super_secreto_123
```

O `wgctl daemon` registra esse token automaticamente no `tokens.json` na primeira subida, permitindo autenticação imediata.

---

## 5. Operação e Comandos Práticos

### Iniciar o container
```bash
docker compose up -d
```

### Acompanhar os logs
```bash
docker compose logs -f
```

### Abrir o Menu TUI Interativo dentro do container
```bash
docker exec -it wgctl wgctl
```

### Gerenciamento Remoto no seu PC / Laptop (Windows, Linux, Mac)
Com o container rodando no servidor, conecte-se a partir de qualquer computador:
```bash
wgctl remote connect https://seu-servidor.com:7443 --token wgctl_tok_meu_token_super_secreto_123
```
Agora execute qualquer comando localmente:
```bash
wgctl status
wgctl peers
wgctl peer add notebook --ip auto
wgctl client notebook --qr
```

---

## 6. Backup e Restauração

Todos os dados persistentes residem no diretório mapeado:
- `./data/wireguard/`: Arquivos de interface (`wg0.conf`), chaves privadas e `tokens.json`.
- `./data/config/`: Perfis e configurações do cliente.

Para fazer backup:
```bash
tar -czvf backup-wireguard-$(date +%F).tar.gz ./data/wireguard
```
Para restaurar, basta descompactar o diretório `./data/wireguard` antes de iniciar o container. O `wgctl` detectará as configurações existentes e iniciará sem modificar nenhum arquivo.
