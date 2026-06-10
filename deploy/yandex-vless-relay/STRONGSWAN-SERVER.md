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

Relay по EAP всё равно обязан проверить сертификат сервера. Нужны те CA, что
образуют цепочку до серверного cert.

### Let's Encrypt (cacerts = isrg-root-x1.pem + letsencrypt-r13.pem)
Если в `ipsec.conf` стоит `leftcert=server-cert.pem` (только лист, без цепочки),
сервер шлёт клиенту только лист — поэтому relay нужны **оба** сертификата:
корень ISRG Root X1 **и** промежуточный R13. Собери их в один файл и скопируй:
```bash
cat /etc/ipsec.d/cacerts/isrg-root-x1.pem /etc/ipsec.d/cacerts/letsencrypt-r13.pem \
    > /root/strongswan-ca.pem
scp /root/strongswan-ca.pem root@<relay_ip>:/root/strongswan-ca.pem
```
В `config.env` relay: `SERVER_CA_CERT="/root/strongswan-ca.pem"` (установщик сам
разложит цепочку по отдельным файлам в `x509ca/`).

> Можно вместо этого на сервере поменять `leftcert=server-cert.pem` на
> `leftcert=server-fullchain.pem` (сервер начнёт слать цепочку) — тогда relay
> хватит одного корня. Но это правка рабочего конфига, не обязательно.

### Self-signed / собственный CA
Скопируй CA-файл (флаг `CA` в `swanctl --list-certs`) или сам self-signed серверный cert.

### SERVER_ID
Должен совпасть с **SAN серверного сертификата**. Для Let's Encrypt это **домен**:
```bash
openssl x509 -in /etc/ipsec.d/certs/server-cert.pem -noout -ext subjectAltName
```
Это же значение, как правило, стоит в `leftid` твоего `/etc/ipsec.conf`.

## Шаг 2b. Фиксированный виртуальный IP для relay

Relay запрашивает конкретный `RELAY_VIP` (по умолчанию `10.10.10.250`) и SNAT'ит
в него трафик юзеров. Этот адрес должен быть **внутри твоего пула** и не выдаваться
другим. Чтобы гарантированно закрепить его за relay, можно завести отдельный conn
под его EAP-логин (legacy `ipsec.conf`):
```conf
conn relay-yandex
    also=<твой_базовый_roadwarrior_conn>   # наследуй существующие параметры
    rightid=relay-yandex                    # = EAP_USERNAME
    rightsourceip=10.10.10.250              # = RELAY_VIP, фиксированно
    auto=add
```
Либо просто проверь, что запрошенный адрес попадает в `rightsourceip`-пул и свободен —
многие конфиги выдают клиенту запрошенный им IP. Если сервер выдал другой адрес
(видно в `swanctl --list-sas` на relay) — впиши его в `RELAY_VIP` на relay и переустанови.

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
