#!/usr/bin/env bash
# Policy-routing для relay: помеченный fwmark'ом трафик XRAY -> отдельная таблица,
# куда charon кладёт маршрут в IPsec-туннель. Плюс blackhole-«kill-switch»,
# чтобы при упавшем туннеле трафик юзеров НЕ утекал напрямую в интернет.
set -euo pipefail

STATE="/etc/yandex-relay/state.env"
[ -r "$STATE" ] && . "$STATE"

FWMARK="${FWMARK:-42}"
ROUTE_TABLE="${ROUTE_TABLE:-100}"
RULE_PRIO=100

resolve_wan() {
    if [ "${WAN_IF:-auto}" = "auto" ] || [ -z "${WAN_IF:-}" ]; then
        ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
    else
        echo "$WAN_IF"
    fi
}

up() {
    # 1) ip rule: трафик с нашим fwmark -> таблица туннеля
    if ! ip rule list | grep -q "fwmark 0x$(printf '%x' "$FWMARK") lookup $ROUTE_TABLE"; then
        ip rule add fwmark "$FWMARK" lookup "$ROUTE_TABLE" priority "$RULE_PRIO"
    fi
    # 2) kill-switch: пока charon не поставил маршрут в туннель (метрика мала),
    #    держим blackhole с большой метрикой -> утечки прямого трафика нет.
    ip route replace blackhole default table "$ROUTE_TABLE" metric 4294967294 2>/dev/null || true
    # 3) rp_filter мешает асимметричным/туннельным маршрутам — ослабляем
    local wan; wan="$(resolve_wan || true)"
    sysctl -qw net.ipv4.conf.all.rp_filter=2 || true
    [ -n "$wan" ] && sysctl -qw "net.ipv4.conf.${wan}.rp_filter=2" 2>/dev/null || true
    echo "[relay-routing] up: fwmark=$FWMARK table=$ROUTE_TABLE wan=${wan:-?}"
}

down() {
    ip rule del fwmark "$FWMARK" lookup "$ROUTE_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
    ip route del blackhole default table "$ROUTE_TABLE" 2>/dev/null || true
    echo "[relay-routing] down"
}

case "${1:-up}" in
    up)   up ;;
    down) down ;;
    *) echo "usage: $0 {up|down}" >&2; exit 2 ;;
esac
