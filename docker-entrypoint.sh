#!/bin/sh
set -e

# Assegura permissões estritas no diretório de configuração do WireGuard
chmod 700 /etc/wireguard 2>/dev/null || true

# 1. Verifica se já existem configurações no volume
has_configs=false
for f in /etc/wireguard/*.conf; do
    [ -e "$f" ] && has_configs=true && break
done

# 2. Executa Auto-Init seguro SOMENTE se não houver configurações existentes
if [ "$has_configs" = "false" ]; then
    if [ "${WGCTL_AUTO_INIT:-true}" = "true" ] || [ "${WGCTL_AUTO_INIT:-true}" = "1" ]; then
        target_iface="${WGCTL_INTERFACE:-wg0}"
        echo "[wgctl-docker] Nenhuma configuração encontrada em /etc/wireguard."
        echo "[wgctl-docker] Inicializando interface '${target_iface}' com parâmetros de ambiente..."

        set -- wgctl init "$target_iface" --non-interactive --skip-packages --no-start
        [ -n "$WGCTL_SUBNET" ] && set -- "$@" --subnet "$WGCTL_SUBNET"
        [ -n "$WGCTL_PORT" ] && set -- "$@" --port "$WGCTL_PORT"
        [ -n "$WGCTL_PUBLIC_IP" ] && set -- "$@" --public-ip "$WGCTL_PUBLIC_IP"
        [ -n "$WGCTL_DNS" ] && set -- "$@" --dns "$WGCTL_DNS"
        [ -n "$WGCTL_WAN" ] && set -- "$@" --wan "$WGCTL_WAN"
        [ -n "$WGCTL_FIRST_CLIENT" ] && set -- "$@" --first-client "$WGCTL_FIRST_CLIENT"
        [ "$WGCTL_NO_FIREWALL" = "true" ] && set -- "$@" --no-firewall

        # Executa a inicialização
        "$@"
        echo "[wgctl-docker] Interface '${target_iface}' inicializada com sucesso!"
    else
        echo "[wgctl-docker] Nenhuma interface encontrada em /etc/wireguard e WGCTL_AUTO_INIT=false."
        echo "[wgctl-docker] Use 'docker exec -it <container> wgctl init' para configurar uma nova interface."
    fi
else
    echo "[wgctl-docker] Configurações existentes detectadas em /etc/wireguard. Preservando arquivos existentes."
fi

# 3. Levanta as interfaces WireGuard configuradas que ainda não estejam ativas
for conf in /etc/wireguard/*.conf; do
    if [ -e "$conf" ]; then
        iface=$(basename "$conf" .conf)
        if ! ip link show "$iface" >/dev/null 2>&1; then
            echo "[wgctl-docker] Levantando interface WireGuard '$iface'..."
            wg-quick up "$conf" || echo "[wgctl-docker] Aviso: Falha ao levantar '$iface' via wg-quick."
        else
            echo "[wgctl-docker] Interface '$iface' já está ativa no kernel."
        fi
    fi
done

# 4. Executa o comando principal repassado ao container
exec "$@"
