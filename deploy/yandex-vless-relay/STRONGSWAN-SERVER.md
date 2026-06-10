# Настройка на стороне strongSwan-сервера (PSK для relay)

Relay подключается **отдельным соединением** по IKEv2 с аутентификацией **PSK**
(не EAP — чтобы не зависеть от eap-mschapv2/md4, которых нет в Ubuntu 24.04).
Сервер по-прежнему предъявляет свой сертификат (relay его проверяет по CA-цепочке).
Существующие EAP-клиенты (телефоны) не затрагиваются — мы лишь **добавляем** conn.

## Шаг 1. Добавить conn для relay (legacy `/etc/ipsec.conf`)

```conf
conn relay-yandex
    keyexchange=ikev2
    left=%any
    leftid=@vm743238.vps.masterhost.tech     # как в существующем leftid
    leftcert=server-cert.pem                  # как в существующем conn
    leftauth=pubkey
    leftsubnet=0.0.0.0/0                       # full-tunnel: весь трафик relay
    right=%any
    rightid=relay-yandex                      # = RELAY_IKE_ID на relay
    rightauth=psk
    rightsourceip=10.10.10.250                # = RELAY_VIP (фиксированный, в пуле)
    rightsubnet=10.10.10.250/32               # УЗКО! не 0.0.0.0/0 — иначе сервер
                                              # завернёт чужой трафик и положит телефоны
    auto=add
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
```

> **Критично:** `rightsubnet` должен быть `/32` (адрес vIP relay), а НЕ `0.0.0.0/0`.
> Широкий TS приводит к политике `0/0===0/0` — сервер заворачивает в туннель к relay
> весь трафик, ломая форвардинг для остальных клиентов (и лочит себя). `leftsubnet`
> остаётся `0.0.0.0/0` — это нормально (relay через сервер ходит «куда угодно»).

## Шаг 2. PSK в `/etc/ipsec.secrets`

PSK сгенерировал установщик; возьми его на relay:
```bash
sudo grep IPSEC_PSK /etc/yandex-relay/state.env      # на relay
```
и пропиши на сервере (тем же значением):
```conf
# /etc/ipsec.secrets
relay-yandex : PSK "ВСТАВЬ_PSK_ИЗ_state.env"
```

Применить без рестарта существующих туннелей:
```bash
sudo ipsec reload
sudo ipsec rereadsecrets
```

## Шаг 3. Трафик relay уходит в XRAY автоматически
Relay получает vIP `10.10.10.250` из пула `10.10.10.0/24`, поэтому твой
существующий NAT/перехват в XRAY (`-s 10.10.10.0/24`) его уже покрывает —
отдельной настройки обычно не требуется. Проверь `net.ipv4.ip_forward=1`.

## Проверка на сервере
```bash
sudo swanctl --list-sas | grep -i relay     # или: sudo ipsec status | grep relay
```
Должна появиться ESTABLISHED SA с id `relay-yandex` и INSTALLED child
(remote_ts = `10.10.10.250/32`).

> Если relay по ошибке попал в общий EAP-conn (в логе сервера видно EAP вместо
> PSK) — убедись, что в conn `relay-yandex` стоит именно `rightid=relay-yandex`
> и что relay шлёт тот же IKE-id (`RELAY_IKE_ID` в config.env).
