#!/usr/bin/env bash
# Быстрая диагностика relay: туннель, маршруты, XRAY, и end-to-end проверка
# выхода через strongSwan (внешний IP должен стать IP strongSwan-сервера/его аплинка).
set -uo pipefail
STATE="/etc/yandex-relay/state.env"
# shellcheck disable=SC1090
[ -r "$STATE" ] && . "$STATE"
FWMARK="${FWMARK:-42}"; ROUTE_TABLE="${ROUTE_TABLE:-100}"

hr(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$1"; }

hr "IPsec (swanctl)";        swanctl --list-sas 2>/dev/null || echo "charon недоступен"
hr "ip rule (fwmark)";       ip rule list | grep -E "fwmark|lookup $ROUTE_TABLE" || echo "нет правила fwmark"
hr "Таблица маршрутов $ROUTE_TABLE"; ip route show table "$ROUTE_TABLE" || true
hr "XRAY";                   systemctl is-active xray; ss -tlnp 2>/dev/null | grep -E ":${XRAY_PORT:-443}\b" || echo "порт не слушается"
hr "nftables MSS clamp";     nft list table inet relay_mangle 2>/dev/null || echo "нет таблицы"

hr "Прямой внешний IP relay (без метки)"
curl -fsS4 --max-time 8 https://api.ipify.org && echo || echo "нет ответа"

hr "Внешний IP ЧЕРЕЗ туннель (через помеченный сокет)"
# curl по умолчанию НЕ ставит fwmark, поэтому помечаем его сокеты явно:
if curl --help all 2>/dev/null | grep -q -- '--mark'; then
    OUT="$(curl -fsS4 --max-time 12 --mark "$FWMARK" https://api.ipify.org 2>/dev/null)"
else
    # старый curl без --mark: помечаем по uid через временное правило nft
    TMPUSER="nobody"
    nft add rule inet relay_mangle output_clamp meta skuid "$TMPUSER" ip daddr != "${STRONGSWAN_SERVER_ADDR:-0.0.0.0}" meta mark set "$FWMARK" 2>/dev/null || true
    OUT="$(sudo -u "$TMPUSER" curl -fsS4 --max-time 12 https://api.ipify.org 2>/dev/null)"
fi
echo "${OUT:-нет ответа}  <- должен совпадать с внешним IP выхода strongSwan, а не с прямым IP relay"
echo
echo "Логи:  journalctl -u xray -u strongswan -n 50 --no-pager"
