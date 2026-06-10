#!/usr/bin/env bash
# Подготовка хоста к mark-gated IPsec. БОЛЬШЕ НЕ трогаем общие маршруты/правила,
# чтобы система не могла заблокировать сама себя. Туннелирование помеченного трафика
# обеспечивают mark_in/mark_out (strongSwan) + SNAT в vIP (nftables).
# Здесь только ослабляем rp_filter (иначе ядро может дропать обратный туннельный трафик).
set -euo pipefail

STATE="/etc/yandex-relay/state.env"
[ -r "$STATE" ] && . "$STATE"

resolve_wan() {
    if [ "${WAN_IF:-auto}" = "auto" ] || [ -z "${WAN_IF:-}" ]; then
        ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
    else
        echo "$WAN_IF"
    fi
}

up() {
    local wan; wan="$(resolve_wan || true)"
    sysctl -qw net.ipv4.conf.all.rp_filter=2 || true
    [ -n "$wan" ] && sysctl -qw "net.ipv4.conf.${wan}.rp_filter=2" 2>/dev/null || true
    echo "[relay-routing] up: rp_filter=2 wan=${wan:-?} (туннель — через mark ${FWMARK:-42})"
}

down() {
    echo "[relay-routing] down (ничего отменять не нужно — маршруты системы не менялись)"
}

case "${1:-up}" in
    up)   up ;;
    down) down ;;
    *) echo "usage: $0 {up|down}" >&2; exit 2 ;;
esac
