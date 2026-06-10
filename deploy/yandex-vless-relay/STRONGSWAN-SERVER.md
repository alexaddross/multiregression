# Настройка на стороне существующего strongSwan-сервера

Relay подключается к серверу как обычный IKEv2 road-warrior с PSK, запрашивает
виртуальный IP из пула и строит **full-tunnel** (`0.0.0.0/0`). Дальше сервер
обрабатывает этот трафик **так же, как трафик любого другого VPN-клиента** —
то есть отправляет его в свой существующий XRAY-outbound. Отдельная точка входа
на конечные серверы не появляется: всё идёт через тот же strongSwan.

> Тебе нужно лишь **добавить одного peer'а** для relay. Ниже — для современного
> `swanctl` (strongSwan 5.9+, Ubuntu 22.04/24.04). Если у тебя legacy
> `/etc/ipsec.conf` — см. вариант в конце.

## Что взять из relay
После `install-relay.sh` значения лежат в `/etc/yandex-relay/state.env`:
- `IPSEC_PSK`     — общий ключ (должен совпасть)
- `RELAY_IKE_ID`  — `leftid` relay (по умолчанию `relay-yandex@vpn.local`)
- `SERVER_IKE_ID` — идентичность сервера (по умолчанию `strongswan@vpn.local`)

## Вариант A — swanctl (`/etc/swanctl/conf.d/relay-peer.conf`)

```conf
connections {
    relay-peer {
        version = 2
        # Relay — инициатор, сервер принимает с любого адреса:
        remote_addrs = %any
        local {
            auth = psk
            id = strongswan@vpn.local         # = SERVER_IKE_ID
        }
        remote {
            auth = psk
            id = relay-yandex@vpn.local        # = RELAY_IKE_ID
        }
        # Выдаём relay адрес из ТВОЕГО существующего пула (как другим клиентам):
        pools = <имя_твоего_pool>             # напр. primary-pool; либо задай rightsourceip
        children {
            relay {
                local_ts  = 0.0.0.0/0          # сервер маршрутизирует весь трафик relay
                remote_ts = dynamic
                esp_proposals = aes256gcm16-prfsha384-ecp384,aes256-sha256-modp2048
            }
        }
        proposals = aes256gcm16-prfsha384-ecp384,aes256-sha256-modp2048
    }
}

secrets {
    ike-relay-peer {
        id-1 = relay-yandex@vpn.local
        secret = "ВСТАВЬ_СЮДА_IPSEC_PSK_ИЗ_state.env"
    }
}
```

Применить без перезапуска:
```bash
sudo swanctl --load-all
sudo swanctl --list-conns | grep relay-peer
```

### Важно: трафик relay должен уходить в XRAY, как у обычных клиентов
Сервер ужеNAT'ит/форвардит трафик VPN-клиентов в свой XRAY — relay получает vIP
из того же пула, поэтому **обычно дополнительная настройка не нужна**. Проверь, что:
- `net.ipv4.ip_forward = 1`;
- правило NAT/перехвата для подсети пула (`iptables -t nat ... -s <pool_subnet>`)
  покрывает адрес, выданный relay (он из того же пула — покрывает);
- firewall разрешает forward с vIP relay.

## Вариант B — legacy `/etc/ipsec.conf` + `/etc/ipsec.secrets`

```conf
# /etc/ipsec.conf
conn relay-peer
    keyexchange=ikev2
    authby=secret
    left=%any
    leftid=strongswan@vpn.local
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=relay-yandex@vpn.local
    rightsourceip=<твой_пул_напр_10.10.10.0/24>
    rightsubnet=0.0.0.0/0
    auto=add
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
```
```conf
# /etc/ipsec.secrets
relay-yandex@vpn.local : PSK "ВСТАВЬ_IPSEC_PSK_ИЗ_state.env"
```
```bash
sudo ipsec reload
```

## Проверка
На сервере после запуска relay:
```bash
sudo swanctl --list-sas | grep -A3 relay-peer     # или: sudo ipsec status
```
Должна появиться ESTABLISHED SA и INSTALLED child с remote_ts = vIP relay.
С relay внешний IP (через помеченный сокет) должен стать выходным IP strongSwan —
см. `status.sh` на relay.
