#!/usr/bin/env bash
# Откат изменений relay (XRAY оставляем установленным; убираем конфиги/маршруты).
set -uo pipefail
[ "$(id -u)" = "0" ] || { echo "Запусти от root."; exit 1; }

systemctl disable --now relay-routing.service 2>/dev/null || true
/usr/local/sbin/relay-routing.sh down 2>/dev/null || true

for SVC in strongswan strongswan-starter; do systemctl disable --now "$SVC" 2>/dev/null || true; done

rm -f /etc/swanctl/conf.d/relay.conf \
      /etc/strongswan.d/99-relay-routing.conf \
      /etc/nftables.d/relay.nft \
      /etc/systemd/system/relay-routing.service \
      /etc/systemd/system/xray.service.d/override.conf \
      /usr/local/sbin/relay-routing.sh \
      /etc/sysctl.d/99-relay.conf
sed -i '\#include "/etc/nftables.d/relay.nft"#d' /etc/nftables.conf 2>/dev/null || true

systemctl daemon-reload
systemctl restart nftables 2>/dev/null || true
systemctl restart xray 2>/dev/null || true
echo "Откат выполнен. Каталог состояния /etc/yandex-relay оставлен (удали вручную при необходимости)."
echo "XRAY-core не удалён: bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ remove"
