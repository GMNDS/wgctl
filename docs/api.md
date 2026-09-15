# wgctl REST API Reference

> **Base URL:** `http(s)://<host>:<port>/api/v1`  
> **Default port:** `7443`  
> **Content-Type:** `application/json` (request e response)  
> **Autenticação:** Bearer token em todas as rotas (exceto `/health`)

---

## Autenticação

Todas as rotas (exceto `/health`) exigem um Bearer token gerado pelo `wgctl daemon token create`.

```http
Authorization: Bearer <token>
```

Gerar token:
```bash
wgctl daemon token create --name "meu-app" --expires 30d
```

---

## Formato de resposta padrão

**Sucesso**
```json
{
  "success": true,
  "data": { ... }
}
```

**Erro**
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Descrição legível do erro"
  }
}
```

### Códigos de erro conhecidos

| Código | HTTP | Descrição |
|--------|------|-----------|
| `NOT_FOUND` | 404 | Rota não existe |
| `INTERFACE_NOT_FOUND` | 404 | Interface WireGuard não encontrada |
| `PEER_NOT_FOUND` | 404 | Peer não encontrado |
| `MISSING_NAME` | 400 | Campo obrigatório `name` ausente |
| `NAME_EXISTS` | 409 | Já existe um peer com esse nome |
| `IP_EXISTS` | 409 | Endereço IP já está alocado |
| `VALIDATION_FAILED` | 400 | Configuração inválida após edição |
| `INVALID_BODY` | 400 | Body da requisição vazio |
| `MALFORMED_JSON` | 400 | JSON inválido no body |
| `SYNC_FAILED` | 500 | Falha ao aplicar configuração com `wg syncconf` |
| `INTERNAL_ERROR` | 500 | Erro interno inesperado |

---

## Endpoints

---

### Health

#### `GET /api/v1/health`

Verifica se o daemon está operacional. Não requer autenticação.

**Response `200`**
```json
{
  "success": true,
  "data": {
    "status": "ok",
    "version": "0.4.3",
    "timestamp": "2026-09-15T21:00:00Z"
  }
}
```

---

### Interfaces

#### `GET /api/v1/interfaces`

Lista os nomes de todas as interfaces WireGuard descobertas no servidor.

**Response `200`**
```json
{
  "success": true,
  "data": ["wg0", "wg1"]
}
```

---

#### `GET /api/v1/interfaces/:name`

Retorna informações detalhadas de uma interface.

**Response `200`**
```json
{
  "success": true,
  "data": {
    "name": "wg0",
    "address": "10.13.14.1/24",
    "listen_port": 51820,
    "public_key": "Dah1LW6/wF5bp4yTZ18faUXxIY+bjEjQxzf8mQEhUUY=",
    "active": true,
    "peer_count": 4,
    "online_peer_count": 2,
    "config_path": "/etc/wireguard/wg0.conf"
  }
}
```

---

#### `POST /api/v1/interfaces/:name/apply`

Aplica a configuração atual ao kernel sem reiniciar (equivalente a `wg syncconf`).

**Response `200`**
```json
{
  "success": true,
  "data": {
    "applied": true,
    "message": "Applied wg0 via wg syncconf"
  }
}
```

---

#### `GET /api/v1/interfaces/:name/check`

Valida e diagnostica a configuração da interface.

**Response `200`**
```json
{
  "success": true,
  "data": {
    "valid": false,
    "issues": [
      {
        "severity": "error",
        "message": "Peer 'notebook' has a duplicate IP 10.13.14.5/32"
      }
    ]
  }
}
```

---

### Peers

#### `GET /api/v1/interfaces/:name/peers`

Lista todos os peers de uma interface.

**Response `200`**
```json
{
  "success": true,
  "data": [
    {
      "name": "notebook",
      "has_name": true,
      "public_key": "YAM0bWDdzO21UJU+eWz1YKQyORTA+SOoP1AjUokHi1o=",
      "allowed_ips": ["10.13.14.2/32"],
      "primary_ip": "10.13.14.2/32",
      "description": "Notebook do escritório",
      "device": "laptop",
      "online": true,
      "endpoint": "200.1.2.3:45678",
      "latest_handshake": "2026-09-15T20:55:00Z",
      "transfer_rx": 1048576,
      "transfer_tx": 2097152
    }
  ]
}
```

---

#### `GET /api/v1/interfaces/:name/peers/:key`

Retorna um peer específico pelo nome ou chave pública. Mesmo schema de objeto acima.

---

#### `POST /api/v1/interfaces/:name/peers`

Adiciona um novo peer.

**Modos:**
- **Managed** (padrão): o servidor gera o par de chaves. A chave privada é retornada uma única vez na resposta.
- **Zero-Knowledge**: forneça `public_key` com a chave pública do cliente. O servidor nunca vê a chave privada.

**Request body**

| Campo | Tipo | Obrigatório | Padrão | Descrição |
|-------|------|-------------|--------|-----------|
| `name` | string | ✅ | — | Nome único |
| `public_key` | string | ❌ | — | Chave pública (ativa modo zero-knowledge) |
| `ip` | string | ❌ | `"auto"` | `"auto"` ou endereço explícito ex: `"10.0.0.5"` |
| `device` | string | ❌ | `"device"` | `phone`, `laptop`, `pc`, `server` |
| `description` | string | ❌ | `""` | Descrição livre |
| `keepalive` | integer | ❌ | `25` | PersistentKeepalive em segundos |

**Response `201`**
```json
{
  "success": true,
  "data": {
    "name": "cel-joao",
    "public_key": "generatedPublicKey==",
    "allowed_ips": ["10.13.14.7/32"],
    "mode": "managed",
    "client_config": "[Interface]\nPrivateKey = generatedPrivateKey==\nAddress = 10.13.14.7/32\n\n[Peer]\n...",
    "qr_text": "▓▓▓▓▓..."
  }
}
```

---

#### `PATCH /api/v1/interfaces/:name/peers/:key`

Edita campos de um peer. Apenas os campos enviados são alterados.

> `PUT` também é aceito com o mesmo comportamento.

**Request body** (todos opcionais)

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `name` | string | Novo nome |
| `description` | string | Nova descrição |
| `device` | string | Tipo de dispositivo |
| `ip` | string | Novo IP (`"auto"` ou explícito) |
| `keepalive` | integer | PersistentKeepalive em segundos |

**Response `200`** — objeto peer atualizado.

---

#### `DELETE /api/v1/interfaces/:name/peers/:key`

Remove um peer permanentemente.

**Response `200`**
```json
{
  "success": true,
  "data": {
    "message": "Peer 'cel-joao' successfully removed from wg0"
  }
}
```

---

### Configuração do cliente

#### `GET /api/v1/interfaces/:name/peers/:key/config`

Retorna o arquivo `.conf` pronto para o dispositivo cliente.

**Negociação de tipo:**
- `Accept: application/json` (padrão) → retorna JSON com campo `config`
- `Accept: text/plain` → retorna o arquivo `.conf` diretamente

**Response `200` (JSON)**
```json
{
  "success": true,
  "data": {
    "name": "notebook",
    "filename": "notebook.conf",
    "config": "[Interface]\nPrivateKey = ...\nAddress = 10.13.14.2/32\n\n[Peer]\n..."
  }
}
```

---

#### `GET /api/v1/interfaces/:name/peers/:key/qr`

Retorna o QR Code ASCII para escanear com o app WireGuard.

**Response `200`**
```json
{
  "success": true,
  "data": {
    "name": "cel-joao",
    "config": "[Interface]\n...",
    "qr_text": "▓▓▓▓▓..."
  }
}
```

---

## Tabela resumo

| Método | Rota | Auth | Descrição |
|--------|------|------|-----------|
| `GET` | `/api/v1/health` | ❌ | Status do daemon |
| `GET` | `/api/v1/interfaces` | ✅ | Listar interfaces |
| `GET` | `/api/v1/interfaces/:name` | ✅ | Detalhes de interface |
| `POST` | `/api/v1/interfaces/:name/apply` | ✅ | Aplicar config ao kernel |
| `GET` | `/api/v1/interfaces/:name/check` | ✅ | Validar configuração |
| `GET` | `/api/v1/interfaces/:name/peers` | ✅ | Listar peers |
| `POST` | `/api/v1/interfaces/:name/peers` | ✅ | Adicionar peer |
| `GET` | `/api/v1/interfaces/:name/peers/:key` | ✅ | Detalhes de peer |
| `PATCH` | `/api/v1/interfaces/:name/peers/:key` | ✅ | Editar peer |
| `DELETE` | `/api/v1/interfaces/:name/peers/:key` | ✅ | Remover peer |
| `GET` | `/api/v1/interfaces/:name/peers/:key/config` | ✅ | Arquivo `.conf` do cliente |
| `GET` | `/api/v1/interfaces/:name/peers/:key/qr` | ✅ | QR Code do cliente |

---

## Exemplos com `curl`

```bash
BASE="http://localhost:7443/api/v1"
TOKEN="tok_seu_token_aqui"

# Health (sem autenticação)
curl "$BASE/health"

# Listar interfaces
curl -H "Authorization: Bearer $TOKEN" "$BASE/interfaces"

# Adicionar peer (modo managed)
curl -X POST "$BASE/interfaces/wg0/peers" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"cel-teste","ip":"auto","device":"phone"}'

# Baixar arquivo .conf diretamente
curl -H "Authorization: Bearer $TOKEN" \
     -H "Accept: text/plain" \
     "$BASE/interfaces/wg0/peers/cel-teste/config" > cel-teste.conf

# Editar peer
curl -X PATCH "$BASE/interfaces/wg0/peers/cel-teste" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"description":"Celular do teste","keepalive":30}'

# Remover peer
curl -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE/interfaces/wg0/peers/cel-teste"
```

---

## Produção: proxy reverso (recomendado)

Rodar o daemon sem TLS e deixar o proxy cuidar da criptografia é mais seguro e flexível.

**Iniciar o daemon ligado apenas ao localhost:**
```bash
sudo wgctl daemon start --port 7443 --host 127.0.0.1
```

**Caddy (TLS automático via Let's Encrypt):**
```
vpn.exemplo.com {
    reverse_proxy localhost:7443
}
```

**Nginx:**
```nginx
server {
    listen 443 ssl;
    server_name vpn.exemplo.com;
    ssl_certificate     /etc/letsencrypt/live/vpn.exemplo.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vpn.exemplo.com/privkey.pem;

    location /api/ {
        proxy_pass         http://127.0.0.1:7443;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        # WebSocket (live metrics)
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
```
