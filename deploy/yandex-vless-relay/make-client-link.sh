#!/usr/bin/env bash
# Печатает готовую vless:// ссылку и QR для импорта в клиент (v2rayN, v2rayNG, NekoBox…)
set -euo pipefail
STATE="/etc/yandex-relay/state.env"
[ -r "$STATE" ] || { echo "Нет $STATE — сначала запусти install-relay.sh"; exit 1; }
# shellcheck disable=SC1090
. "$STATE"

HOST="${RELAY_PUBLIC_IP:-RELAY_IP}"
SNI="${REALITY_SERVERNAMES%%,*}"   # первый из serverNames
LINK="vless://${VLESS_UUID}@${HOST}:${XRAY_PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&flow=xtls-rprx-vision&type=tcp#yandex-relay"

echo "==================== КЛИЕНТСКИЙ КОНФИГ ===================="
echo "Адрес (relay) : ${HOST}:${XRAY_PORT}"
echo "UUID          : ${VLESS_UUID}"
echo "Public key    : ${REALITY_PUBLIC_KEY}"
echo "Short ID      : ${REALITY_SHORT_ID}"
echo "SNI / dest    : ${SNI}  (маскировка)"
echo "Flow          : xtls-rprx-vision"
echo "----------------------------------------------------------"
echo "$LINK"
echo "=========================================================="
if command -v qrencode >/dev/null 2>&1; then
    echo "QR-код:"
    qrencode -t ANSIUTF8 "$LINK"
fi
