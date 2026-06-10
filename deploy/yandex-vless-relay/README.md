# Yandex Cloud relay: XRAY VLESS+REALITY → strongSwan

Ретранслятор на ВМ Yandex Compute Cloud: принимает клиентов по **VLESS + REALITY**
(устойчиво к ТСПУ/DPI) и заворачивает их трафик в **IKEv2/IPsec-туннель** до уже
существующего **strongSwan-сервера**, который и выпускает запросы дальше через свой
XRAY-outbound. Цель — добавить вход, не плодя вторую точку входа на конечные серверы.

```
Клиент (РФ, за DPI)
   │  VLESS + REALITY  :443   (маскировка под whitelist-домен)
   ▼
Yandex Cloud relay (РФ)            ← ставим этими скриптами
   │  XRAY freedom-out + sockopt.mark=42
   │  SNAT в vIP + mark-gated IPsec-политика (mark_in/mark_out=42)
   │  IKEv2/IPsec (EAP, фиксированный vIP)
   ▼
strongSwan-сервер (РФ, уже работает)
   │  существующий XRAY-outbound
   ▼
заблокированные сервисы
```

В туннель уходит **только** помеченный (fwmark 42) трафик юзеров — за счёт
mark-gated IPsec-политики. SSH, ICMP, IKE/ESP и ответы VLESS-клиентам идут
напрямую и **физически не могут** попасть в туннель, поэтому сервер не способен
заблокировать сам себя. `charon.install_routes=no` — маршруты системы не трогаются.

> **Предохранитель.** Установщик перед поднятием туннеля взводит deadman-таймер:
> через 10 минут relay авто-откатится и вернёт прямой доступ, если ты не отменишь
> его командой `sudo systemctl stop relay-deadman.timer`. Так первый запуск
> безопасен, даже если конфиг неверный.

> Почему скриптами, а не «зайди и настрой»: среда Claude Code здесь —
> эфемерный контейнер без SSH-клиента и без исходящей сети, ключ в ней не живёт
> между сессиями. Поэтому ты клонируешь репозиторий на ВМ и запускаешь сам.

## Состав
| Файл | Назначение |
|------|------------|
| `config.env.example` | входные параметры (IP сервера, домен-маскировка, …) |
| `install-relay.sh` | основной установщик (на ВМ Yandex Cloud) |
| `make-client-link.sh` | печатает `vless://`-ссылку и QR |
| `status.sh` | диагностика туннеля/маршрутов/XRAY |
| `uninstall-relay.sh` | откат |
| `STRONGSWAN-SERVER.md` | что добавить на существующем strongSwan |
| `templates/` | шаблоны конфигов XRAY / swanctl / nftables / systemd |

## Предусловия (Yandex Cloud)
1. ВМ Ubuntu **22.04 или 24.04**, публичный IP.
2. **Security group / firewall**:
   - входящий **TCP 443** (вход VLESS) — отовсюду;
   - входящий **TCP 22** — со своего IP (управление);
   - исходящий **UDP 500 и 4500** к IP strongSwan-сервера (IKE/IPsec, encap=yes);
   - исходящий к `REALITY_DEST` (443) — для REALITY-handshake.
3. На strongSwan: **EAP-учётка** для relay (логин/пароль) + его **CA-сертификат**
   (см. `STRONGSWAN-SERVER.md`). Учётку можно переиспользовать существующую.

## Установка
```bash
# на ВМ Yandex Cloud
git clone <этот-репозиторий> && cd <repo>/deploy/yandex-vless-relay
# скопируй CA сервера на relay (см. STRONGSWAN-SERVER.md, шаг 2). Для Let's Encrypt:
#   cat .../isrg-root-x1.pem .../letsencrypt-r13.pem > /root/strongswan-ca.pem
#   scp /root/strongswan-ca.pem root@<relay_ip>:/root/strongswan-ca.pem
cp config.env.example config.env
nano config.env            # заполни: STRONGSWAN_SERVER_ADDR, EAP_USERNAME, EAP_PASSWORD,
                           #          SERVER_ID, SERVER_CA_CERT; домен можно оставить dzen.ru
sudo ./install-relay.sh
```
Скрипт сам сгенерирует UUID, ключи REALITY (x25519) и shortId, сохранит состояние в
`/etc/yandex-relay/state.env`, поднимет XRAY + strongSwan (EAP-клиент) + маршрутизацию
и в конце напечатает клиентскую `vless://`-ссылку с QR.

Затем на **strongSwan-сервере** заведи EAP-юзера по `STRONGSWAN-SERVER.md`
(логин/пароль = `EAP_USERNAME`/`EAP_PASSWORD` из `config.env`).

## Домен-маскировка (REALITY)
По требованию — домен из «белых списков» РФ, чтобы ТСПУ не резало. Дефолт `dzen.ru`
(Yandex, relay сам в Yandex Cloud — выглядит органично, TLS 1.3 + HTTP/2). Альтернативы:
`ya.ru`, `vk.com`. Перед использованием проверь на ВМ:
```bash
openssl s_client -connect dzen.ru:443 -tls1_3 -alpn h2 </dev/null 2>/dev/null | grep -E "Protocol|ALPN"
```
Должно быть `TLSv1.3` и `ALPN protocol: h2`. Меняется в `config.env`
(`REALITY_DEST`, `REALITY_SERVERNAMES`) до установки.

## Проверка (важно — в течение 10 минут!)
Открой **вторую** SSH-сессию (первую не закрывай) и убедись, что доступ жив. Затем:
```bash
sudo ./status.sh
```
- `swanctl --list-sas` → SA `ESTABLISHED`/`INSTALLED`;
- vIP `RELAY_VIP` присутствует на интерфейсе;
- внешний IP через помеченный сокет ≠ прямой IP relay и совпадает с выходом strongSwan;
- импортируй `vless://`-ссылку в v2rayNG / NekoBox / v2rayN и проверь доступ.

Если всё работает — **отмени предохранитель**, иначе через 10 мин relay откатится:
```bash
sudo systemctl stop relay-deadman.timer
```

## Траблшутинг
- **Потерял доступ после установки** → ничего не делай, через 10 мин deadman сам
  откатит relay и вернёт SSH. (Это safety-net; в новой схеме сервер не должен
  лочить сам себя, но предохранитель страхует от любых сюрпризов.)
- **SA не поднимается** → не совпал логин/пароль EAP; `SERVER_ID` ≠ SAN серверного
  сертификата; не тот CA в `SERVER_CA_CERT`; либо UDP 500/4500 закрыты в security
  group. Логи: `journalctl -u strongswan -n 80` (ищи `EAP failed` / `no trusted
  certificate` / `IDr mismatch`).
- **VLESS коннектится, но нет интернета** → (1) сервер выдал vIP, отличный от
  `RELAY_VIP` (смотри `swanctl --list-sas`) → впиши выданный в `RELAY_VIP` и
  переустанови; (2) сервер не NAT'ит этот vIP в XRAY; (3) нет SNAT-правила —
  проверь `nft list table ip relay_nat`.
- **REALITY рвётся / палится** → `REALITY_DEST` недоступен с ВМ или не TLS 1.3.
  Проверь командой `openssl s_client` выше, смени домен.
- **Тормозит/виснут крупные страницы** → MTU. Уменьши `TUNNEL_MSS` (напр. 1300)
  в `config.env` и переустанови, либо поправь `/etc/nftables.d/relay.nft`.

## Безопасность
- `state.env` (пароль EAP, приватный ключ REALITY) — `chmod 600`, не коммить.
- Ограничь SSH своим IP; на 443 — только REALITY.
- Это инфраструктура для собственного доступа; используй ответственно и легально.
