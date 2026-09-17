# ==============================================================================
# Stage 1: Build estático do binário com Crystal no Alpine Linux
# ==============================================================================
FROM crystallang/crystal:1.15-alpine AS builder

WORKDIR /build

COPY shard.yml ./
COPY src/ src/

RUN shards build --release --no-debug --static

# ==============================================================================
# Stage 2: Runtime enxuto e seguro (Alpine Linux)
# ==============================================================================
FROM alpine:3.19

# Instala ferramentas essenciais do WireGuard, firewall e suporte a QR Code
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    ca-certificates \
    qrencode \
    tzdata

# Copia o binário estático e o script de inicialização
COPY --from=builder /build/bin/wgctl /usr/local/bin/wgctl
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/wgctl /usr/local/bin/docker-entrypoint.sh

WORKDIR /etc/wireguard

# Portas padrão: WireGuard UDP (51820) e REST API TCP (7443)
EXPOSE 51820/udp
EXPOSE 7443/tcp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Comando padrão: inicia o daemon REST em foreground
CMD ["wgctl", "daemon", "start", "--foreground", "--host", "0.0.0.0", "--port", "7443"]
