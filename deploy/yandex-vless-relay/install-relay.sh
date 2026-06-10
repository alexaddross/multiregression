#!/usr/bin/env bash
# =============================================================================
#  Установщик relay: XRAY VLESS+REALITY (вход) -> IPsec-туннель к strongSwan.
#  Запускать НА ВМ Yandex Cloud (Ubuntu 22.04/24.04) от root:
#      sudo ./install-relay.sh [path/to/config.env]
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/templates"
STATE_DIR="/etc/yandex-relay"
STATE="$STATE_DIR/state.env"

[ "$(id -u)" = "0" ] || { echo "Запусти от root (sudo)."; exit 1; }

CFG="${1:-$HERE/config.env}"
if [ ! -r "$CFG" ]; then
    echo "Нет config.env. Скопируй пример и заполни:"
    echo "    cp $HERE/config.env.example $HERE/config.env && nano $HERE/config.env"
    exit 1
fi
# shellcheck disable=SC1090
. "$CFG"

log() { printf '\033[1;36m[relay]\033[0m %s\n' "$*"; }

# ---- 1. Пакеты --------------------------------------------------------------
log "Установка пакетов…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# Без --no-install-recommends: нужны плагины eap-mschapv2 + md4 (libcharon/libstrongswan-extra)
apt-get install -y \
    strongswan strongswan-swanctl \
    libcharon-extra-plugins libstrongswan-extra-plugins libstrongswan-standard-plugins \
    nftables curl jq qrencode openssl iproute2 ca-certificates perl

# ---- 1c. Модули ядра IPsec (на части облачных образов заблокированы) ---------
# Без esp4 ядро не ставит ESP SA: "unable to add SAD entry". На хардненных образах
# модули блокируют строкой `install esp4 /bin/false` — снимаем такие блокировки.
RELAY_KMODS="af_key esp4 esp6 ah4 xfrm_user xfrm_algo authenc"
KRE="$(printf '%s|' $RELAY_KMODS | sed 's/|$//')"
grep -rlE "install +($KRE) +/bin/(false|true)" \
     /etc/modprobe.d /usr/lib/modprobe.d /lib/modprobe.d 2>/dev/null | while read -r f; do
    sed -ri "s@^(\s*install\s+($KRE)\s+/bin/(false|true).*)@# disabled-by-relay: \1@" "$f"
    log "Снята блокировка IPsec-модулей в $f"
done
for m in $RELAY_KMODS; do modprobe --ignore-install "$m" 2>/dev/null || modprobe "$m" 2>/dev/null || true; done
printf '%s\n' $RELAY_KMODS > /etc/modules-load.d/relay-ipsec.conf

# ---- 2. XRAY ----------------------------------------------------------------
if ! command -v xray >/dev/null 2>&1; then
    log "Установка XRAY-core (официальный installer)…"
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
    log "XRAY уже установлен: $(xray version | head -1)"
fi

# ---- 3a. Проверка/нормализация параметров -----------------------------------
: "${STRONGSWAN_SERVER_ADDR:?Укажи STRONGSWAN_SERVER_ADDR в config.env}"
: "${SERVER_ID:?Укажи SERVER_ID (SAN серверного сертификата) в config.env}"
# Дефолты для необязательных полей (чтобы рендер под set -u не падал)
RELAY_IKE_ID="${RELAY_IKE_ID:-relay-yandex}"
XRAY_PORT="${XRAY_PORT:-443}"
REALITY_DEST="${REALITY_DEST:-dzen.ru:443}"
REALITY_SERVERNAMES="${REALITY_SERVERNAMES:-dzen.ru}"
RELAY_VIP="${RELAY_VIP:-10.10.10.250}"
FWMARK="${FWMARK:-42}"
TUNNEL_MSS="${TUNNEL_MSS:-1360}"
WAN_IF="${WAN_IF:-auto}"
if [ -z "${SERVER_CA_CERT:-}" ] || [ ! -r "${SERVER_CA_CERT:-}" ]; then
    echo "Не найден CA-сертификат сервера: SERVER_CA_CERT='${SERVER_CA_CERT:-}'"
    echo "Relay проверяет сертификат сервера. Скопируй CA-цепочку на relay и укажи путь."
    exit 1
fi

# ---- 3b. Секреты (генерируем недостающие) -----------------------------------
log "Подготовка секретов…"
[ -n "${IPSEC_PSK:-}" ]       || IPSEC_PSK="$(openssl rand -hex 32)"
[ -n "${VLESS_UUID:-}" ]      || VLESS_UUID="$(xray uuid)"
[ -n "${REALITY_SHORT_ID:-}" ] || REALITY_SHORT_ID="$(openssl rand -hex 8)"
if [ -z "${REALITY_PRIVATE_KEY:-}" ] || [ -z "${REALITY_PUBLIC_KEY:-}" ]; then
    KP="$(xray x25519)"
    REALITY_PRIVATE_KEY="$(printf '%s\n' "$KP" | awk -F': *' '/[Pp]rivate/{print $2}' | tr -d '[:space:]')"
    REALITY_PUBLIC_KEY="$(printf '%s\n'  "$KP" | awk -F': *' '/[Pp]ublic/{print  $2}' | tr -d '[:space:]')"
fi

# Определяем публичный IP relay (для клиентской ссылки)
RELAY_PUBLIC_IP="$(curl -fsS4 https://api.ipify.org 2>/dev/null || \
                   ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"

# ---- 4. Сохраняем состояние -------------------------------------------------
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
cat > "$STATE" <<EOF
# Сгенерировано install-relay.sh $(date -u +%FT%TZ)
STRONGSWAN_SERVER_ADDR="$STRONGSWAN_SERVER_ADDR"
RELAY_IKE_ID="$RELAY_IKE_ID"
IPSEC_PSK="$IPSEC_PSK"
SERVER_ID="$SERVER_ID"
SERVER_CA_CERT="$SERVER_CA_CERT"
XRAY_PORT="$XRAY_PORT"
REALITY_DEST="$REALITY_DEST"
REALITY_SERVERNAMES="$REALITY_SERVERNAMES"
VLESS_UUID="$VLESS_UUID"
REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY"
REALITY_PUBLIC_KEY="$REALITY_PUBLIC_KEY"
REALITY_SHORT_ID="$REALITY_SHORT_ID"
RELAY_VIP="${RELAY_VIP:-10.10.10.250}"
FWMARK="${FWMARK:-42}"
TUNNEL_MSS="${TUNNEL_MSS:-1360}"
WAN_IF="${WAN_IF:-auto}"
RELAY_PUBLIC_IP="$RELAY_PUBLIC_IP"
EOF
chmod 600 "$STATE"

# ---- 5. Рендер шаблонов -----------------------------------------------------
render() {  # render <tpl> <out> ; подстановка __NAME__ из текущего окружения
    local tpl="$1" out="$2"
    cp "$tpl" "$out.tmp"
    for name in XRAY_PORT VLESS_UUID REALITY_DEST REALITY_SERVERNAMES \
                REALITY_PRIVATE_KEY REALITY_SHORT_ID FWMARK RELAY_VIP \
                TUNNEL_MSS STRONGSWAN_SERVER_ADDR RELAY_IKE_ID IPSEC_PSK SERVER_ID; do
        VAL="${!name}" perl -i -pe "s/__${name}__/\$ENV{VAL}/g" "$out.tmp"
    done
    mv "$out.tmp" "$out"
}

log "Генерация конфигов…"
install -d /usr/local/etc/xray /etc/swanctl/conf.d /etc/swanctl/x509ca /etc/strongswan.d \
           /etc/nftables.d /etc/systemd/system/xray.service.d

# CA-сертификат(ы) сервера -> swanctl проверит ими сертификат strongSwan при EAP.
# Файл может содержать НЕСКОЛЬКО сертификатов (корень + промежуточный) — разложим по одному.
rm -f /etc/swanctl/x509ca/relay-ca-*.pem
if [ "$(grep -c 'BEGIN CERTIFICATE' "$SERVER_CA_CERT")" -gt 1 ]; then
    csplit -sz -f /etc/swanctl/x509ca/relay-ca- -b '%02d.pem' \
           "$SERVER_CA_CERT" '/BEGIN CERTIFICATE/' '{*}'
    chmod 0644 /etc/swanctl/x509ca/relay-ca-*.pem
    log "CA сервера установлен (цепочка): $(ls /etc/swanctl/x509ca/relay-ca-*.pem | wc -l) cert(s)"
else
    install -m 0644 "$SERVER_CA_CERT" /etc/swanctl/x509ca/relay-ca-00.pem
    log "CA сервера установлен: /etc/swanctl/x509ca/relay-ca-00.pem"
fi

render "$TPL/xray-config.template.json"        /usr/local/etc/xray/config.json
render "$TPL/swanctl-relay.template.conf"       /etc/swanctl/conf.d/relay.conf
render "$TPL/strongswan-routing.template.conf"  /etc/strongswan.d/99-relay-routing.conf
render "$TPL/nftables-relay.template.nft"       /etc/nftables.d/relay.nft
chmod 600 /etc/swanctl/conf.d/relay.conf

cp "$TPL/xray-override.conf"   /etc/systemd/system/xray.service.d/override.conf
cp "$TPL/relay-routing.service" /etc/systemd/system/relay-routing.service
install -m 0755 "$HERE/relay-routing.sh"  /usr/local/sbin/relay-routing.sh
install -m 0755 "$HERE/relay-deadman.sh"  /usr/local/sbin/relay-deadman.sh

# nftables: подключаем наш файл из основного конфига
if ! grep -q '/etc/nftables.d/relay.nft' /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/relay.nft"' >> /etc/nftables.conf
fi

# ---- 6. sysctl --------------------------------------------------------------
cat > /etc/sysctl.d/99-relay.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF
sysctl -q --system || true

# ---- 7. ПРЕДОХРАНИТЕЛЬ (deadman) до поднятия туннеля -------------------------
# Если что-то пойдёт не так и связь пропадёт — через 10 минут relay сам откатится
# и вернёт прямой доступ. Отменишь вручную, когда убедишься, что всё работает.
DEADMAN_MIN="${DEADMAN_MIN:-10}"
systemctl stop relay-deadman.timer 2>/dev/null || true
systemd-run --on-active="${DEADMAN_MIN}min" --unit=relay-deadman \
    --description="relay deadman auto-rollback" \
    /usr/local/sbin/relay-deadman.sh >/dev/null 2>&1 || true
log "Взведён предохранитель: авто-откат через ${DEADMAN_MIN} мин, если не отменить."

# ---- 8. Запуск служб --------------------------------------------------------
log "Запуск служб…"
systemctl daemon-reload
systemctl enable --now nftables
nft -f /etc/nftables.conf
systemctl enable --now relay-routing.service

SS_SVC="strongswan"
systemctl list-unit-files | grep -q '^strongswan.service' || SS_SVC="strongswan-starter"
systemctl enable "$SS_SVC"
systemctl restart "$SS_SVC"   # restart (не enable --now): подхватить md4 в charon
sleep 2
swanctl --load-all
swanctl --initiate --child tunnel 2>/dev/null || true

systemctl enable xray
systemctl restart xray

# ---- 9. Итог ----------------------------------------------------------------
log "Готово. Состояние сохранено в $STATE"
echo
"$HERE/make-client-link.sh" || true
echo
printf '\033[1;33m%s\033[0m\n' "================== ВАЖНО: ПРЕДОХРАНИТЕЛЬ ВЗВЕДЁН =================="
echo "Через ${DEADMAN_MIN} минут relay АВТОМАТИЧЕСКИ отключится и вернёт прямой доступ,"
echo "если ты не отменишь предохранитель. Сначала убедись, что:"
echo "  1) SSH к серверу по-прежнему жив (открой ВТОРУЮ сессию, не закрывая эту);"
echo "  2) туннель поднялся:   sudo $HERE/status.sh"
echo "Если всё ок — ОТМЕНИ авто-откат:"
printf '   \033[1;32msudo systemctl stop relay-deadman.timer\033[0m\n'
echo "Если связь пропала — просто подожди ${DEADMAN_MIN} мин, доступ вернётся сам."
printf '\033[1;33m%s\033[0m\n' "=================================================================="
echo
log "На strongSwan-сервере добавь PSK-conn для relay (id '$RELAY_IKE_ID', vIP $RELAY_VIP)."
log "PSK для сервера: $(grep -oP 'IPSEC_PSK=\"\K[^\"]+' "$STATE")"
