# Настройка на стороне существующего strongSwan-сервера (EAP, логин/пароль)

У тебя road-warrior'ы аутентифицируются по **EAP-MSCHAPv2** (логин/пароль) —
значит relay подключается **как обычный VPN-юзер**. Скорее всего на сервере уже
всё настроено для приёма таких клиентов (сертификат сервера, пул адресов, NAT в
XRAY). Тебе нужно лишь **завести учётку для relay** (или переиспользовать существующую)
и отдать relay **CA-сертификат**, которым он проверит сервер.

## Шаг 1. Завести EAP-юзера для relay

### swanctl (strongSwan 5.9+, Ubuntu 22.04/24.04)
Добавь в `secrets {}` (например в `/etc/swanctl/conf.d/eap-users.conf` или туда,
где у тебя уже лежат юзеры):
```conf
secrets {
    eap-relay {
        id = relay-yandex          # = EAP_USERNAME из config.env
        secret = "тот_же_пароль"    # = EAP_PASSWORD из config.env
    }
}
```
Применить без рестарта:
```bash
sudo swanctl --load-all
```

### legacy `/etc/ipsec.secrets`
```conf
relay-yandex : EAP "тот_же_пароль"
```
```bash
sudo ipsec rereadsecrets
```

> Если используешь общий аккаунт для всех клиентов — просто возьми его логин/пароль
> и впиши в `config.env` relay, ничего нового заводить не нужно.
> Если EAP проверяется через RADIUS — заведи юзера в RADIUS, на strongSwan менять нечего.

## Шаг 2. Отдать relay CA-сертификат сервера

Relay по EAP всё равно обязан проверить сертификат сервера. Нужен тот самый
**CA**, который импортируют твои обычные VPN-клиенты (на сервере это обычно
`/etc/swanctl/x509ca/ca.pem`, либо self-signed серверный cert). Скопируй его на relay:
```bash
# с сервера на relay:
scp /etc/swanctl/x509ca/ca.pem root@<relay_ip>:/root/strongswan-ca.pem
```
и укажи путь в `config.env` relay: `SERVER_CA_CERT="/root/strongswan-ca.pem"`.

`SERVER_ID` в `config.env` должен совпасть с **SAN серверного сертификата**.
Посмотреть SAN:
```bash
openssl x509 -in /etc/swanctl/x509certs/server.pem -noout -text | grep -A1 "Subject Alternative Name"
```
Если там IP — ставь IP сервера; если домен — домен.

## Шаг 3. Трафик relay уходит в XRAY автоматически
Relay получает vIP из того же пула, что и остальные клиенты, поэтому твой
существующий NAT/перехват в XRAY (`-s <pool_subnet>`) его уже покрывает —
отдельной настройки обычно не требуется. Проверь только, что `net.ipv4.ip_forward=1`
и firewall разрешает forward с адресов пула.

## Проверка на сервере
```bash
sudo swanctl --list-sas | grep -i relay      # или: sudo ipsec status
```
Должна появиться `ESTABLISHED` SA с EAP-identity `relay-yandex` и INSTALLED child
(remote_ts = выданный relay vIP).
