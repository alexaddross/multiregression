#!/usr/bin/env bash
# ПРЕДОХРАНИТЕЛЬ. Запускается отложенным таймером после установки. Если админ НЕ
# отменил его (значит, скорее всего, потерял доступ) — откатывает relay в безопасное
# состояние: гасит туннель и отключает автозапуск, возвращая прямую связь.
# Отмена (когда убедился, что доступ есть):  sudo systemctl stop relay-deadman.timer
set +e

logger -t relay-deadman "СРАБОТАЛ предохранитель: откатываю relay для восстановления доступа"

swanctl --terminate --ike relay-to-strongswan 2>/dev/null
for SVC in strongswan strongswan-starter relay-routing.service; do
    systemctl disable --now "$SVC" 2>/dev/null
done
/usr/local/sbin/relay-routing.sh down 2>/dev/null

# Снимаем nftables-правила relay (SNAT/clamp), чтобы наверняка не мешали
nft delete table ip relay_nat 2>/dev/null
nft delete table inet relay_mangle 2>/dev/null

logger -t relay-deadman "relay отключён, прямой доступ восстановлен. Проверь конфиг и запусти заново."
