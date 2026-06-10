#!/usr/bin/env bash
# Быстрая диагностика relay: туннель, политики, XRAY, и end-to-end проверка
# выхода через strongSwan (внешний IP должен стать IP выхода strongSwan).
set -uo pipefail
STATE="/etc/yandex-relay/state.env"
# shellcheck disable=SC1090
[ -r "$STATE" ] && . "$STATE"
FWMARK="${FWMARK:-42}"; RELAY_VIP="${RELAY_VIP:-10.10.10.250}"

hr(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$1"; }

hr "Предохранитель (deadman)"
if systemctl is-active --quiet relay-deadman.timer; then
    echo "ВЗВЕДЁН — если всё работает, отмени: sudo systemctl stop relay-deadman.timer"
else
    echo "снят (или не взводился)"
fi

hr "IPsec (swanctl)";   swanctl --list-sas 2>/dev/null || echo "charon недоступен"
hr "vIP назначен?";     ip -4 addr | grep -q "$RELAY_VIP" && echo "$RELAY_VIP присутствует" || echo "vIP $RELAY_VIP не найден (сервер выдал другой? проверь --list-sas)"
hr "XFRM-политики (mark $FWMARK)"; ip xfrm policy 2>/dev/null | grep -A2 -i "mark" || echo "нет mark-политик"
hr "nftables (SNAT + clamp)"; nft list table ip relay_nat 2>/dev/null; nft list table inet relay_mangle 2>/dev/null || echo "нет таблиц"
hr "XRAY";              systemctl is-active xray; ss -tlnp 2>/dev/null | grep -E ":${XRAY_PORT:-443}\b" || echo "порт не слушается"

hr "Прямой внешний IP relay (без метки)"
curl -fsS4 --max-time 8 https://api.ipify.org && echo || echo "нет ответа"

hr "Внешний IP ЧЕРЕЗ туннель (помеченный сокет)"
if curl --help all 2>/dev/null | grep -q -- '--mark'; then
    OUT="$(curl -fsS4 --max-time 12 --mark "$FWMARK" https://api.ipify.org 2>/dev/null)"
    echo "${OUT:-нет ответа}  <- должен совпадать с внешним IP выхода strongSwan, не с прямым IP relay"
else
    echo "curl без --mark; проверь с реального клиента, подключившись по VLESS."
fi
echo
echo "Логи:  journalctl -u xray -u strongswan -n 50 --no-pager"
