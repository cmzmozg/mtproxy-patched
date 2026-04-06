# mtproxy-patched

MTProxy-сервер для Telegram с маскировкой трафика, оптимизациями и фиксом загрузки видео.

Работает в двух режимах:
- **Через SOCKS5** — трафик уходит в любой поднятый туннель на localhost (xray, sing-box, SSH, Shadowsocks)
- **Директ** — прокси подключается к Telegram напрямую (для серверов за VPN/IPsec где весь трафик уже идёт через туннель на уровне ОС)

Для Telegram-клиента это обычный MTProxy — одна ссылка `tg://proxy`, никаких настроек на стороне юзера.

---

## Какой режим выбрать

### SOCKS5 — когда на сервере поднят туннель с SOCKS5 inbound

Прокси отправляет трафик в `127.0.0.1:1080`. На этом порту должен слушать xray, sing-box, SSH-туннель или любой другой софт, который пробрасывает трафик через зарубежный сервер.

```
Telegram --> MTProxy --> SOCKS5 :1080 --> xray/sing-box --> зарубежный сервер --> Telegram DC
```

Используйте если у вас настроена связка: РФ-нода + xray/sing-box с outbound на евро-ноду.

### Директ — когда сервер уже за VPN/IPsec

Весь трафик сервера уже идёт через туннель на уровне системы (IPsec, WireGuard, OpenVPN). Прокси подключается к Telegram "напрямую", но фактически трафик уходит через туннель — потому что так настроена маршрутизация на сервере.

```
Telegram --> MTProxy --> (VPN/IPsec на уровне ОС) --> Telegram DC
```

Используйте если у вас VPN-роутер, VPS с полным VPN-туннелем, или сервер за IPsec.

---

## Требования

- Ubuntu 20.04+ / Debian 11+ (или любой Linux с Python 3.7+)
- Root-доступ
- Для режима SOCKS5: работающий SOCKS5 на `127.0.0.1:1080`
- Для режима директ: VPN/IPsec который маршрутизирует трафик к IP Telegram

### Установка Docker (если не установлен)

```bash
curl -fsSL https://get.docker.com | sh
```

---

## Установка

### Вариант 1: Нативная (без Docker)

**С SOCKS5 (xray/sing-box на localhost:1080):**

```bash
curl -sL https://raw.githubusercontent.com/cmzmozg/mtproxy-patched/main/install-native.sh -o install.sh
sudo MT_SOCKS5_HOST=127.0.0.1 MT_SOCKS5_PORT=1080 bash install.sh
```

**Директ (сервер за VPN/IPsec):**

```bash
curl -sL https://raw.githubusercontent.com/cmzmozg/mtproxy-patched/main/install-native.sh -o install.sh
sudo bash install.sh
```

Разница — только `MT_SOCKS5_HOST` и `MT_SOCKS5_PORT`. Есть — трафик в SOCKS5. Нет — директ.

**Параметры (опционально):**

```bash
# Первый аргумент — порт, второй — домен маскировки
sudo bash install.sh 853 habr.com

# Или через переменные
MT_PORT=443 MT_SECRET=abcdef1234567890abcdef1234567890 MT_TLS_DOMAIN=habr.com sudo bash install.sh
```

**Управление:**

```bash
systemctl status mtproxy        # статус
systemctl restart mtproxy       # перезапуск
journalctl -fu mtproxy          # логи
cat /opt/mtproxy/secret.txt     # секрет
```

---

### Вариант 2: Docker

**С SOCKS5:**

```bash
PORT=853
mkdir -p /opt/mtproxy && cat > /opt/mtproxy/docker-compose.yml << EOF
services:
  mtproxy:
    image: ghcr.io/cmzmozg/mtproxy-patched:latest
    container_name: mtproxy
    restart: always
    network_mode: host
    environment:
      - MT_PORT=${PORT}
      - MT_SECRET=auto
      - MT_TLS_DOMAIN=habr.com
      - MT_SOCKS5_HOST=127.0.0.1
      - MT_SOCKS5_PORT=1080
EOF

ufw allow ${PORT}/tcp 2>/dev/null
cd /opt/mtproxy && docker compose up -d
sleep 5
IP=$(curl -4 -s ifconfig.me)
docker logs mtproxy 2>&1 | grep "tg://proxy" | grep "${IP}" | head -1
```

**Директ (без SOCKS5):**

```bash
PORT=853
mkdir -p /opt/mtproxy && cat > /opt/mtproxy/docker-compose.yml << EOF
services:
  mtproxy:
    image: ghcr.io/cmzmozg/mtproxy-patched:latest
    container_name: mtproxy
    restart: always
    network_mode: host
    environment:
      - MT_PORT=${PORT}
      - MT_SECRET=auto
      - MT_TLS_DOMAIN=habr.com
EOF

ufw allow ${PORT}/tcp 2>/dev/null
cd /opt/mtproxy && docker compose up -d
sleep 5
IP=$(curl -4 -s ifconfig.me)
docker logs mtproxy 2>&1 | grep "tg://proxy" | grep "${IP}" | head -1
```

**Управление:**

```bash
docker logs -f mtproxy                     # логи
cd /opt/mtproxy && docker compose restart   # перезапуск
cd /opt/mtproxy && docker compose pull      # обновление образа
cd /opt/mtproxy && docker compose up -d     # применить обновление
```

---

## Как работает

```
Telegram-клиент
    |
    |  FakeTLS (провайдер видит HTTPS к habr.com)
    v

+--------------------------------------------+
|  MTProxy (:853)                            |
|                                            |
|  SOCKS5 указан:                            |
|    трафик -> 127.0.0.1:1080 -> туннель     |
|                                            |
|  SOCKS5 не указан:                         |
|    трафик -> Telegram DC напрямую          |
|    (VPN/IPsec заворачивает на уровне ОС)   |
+--------------------------------------------+
```

MTProxy не знает что стоит за SOCKS5 — xray, sing-box, SSH, что угодно. Можно менять туннель без перенастройки прокси и клиентов.

**Совместимые туннели (что может слушать на `127.0.0.1:1080`):**

| Туннель | Пример |
|---|---|
| xray / v2ray | `"inbounds": [{"protocol": "socks", "port": 1080, "listen": "127.0.0.1"}]` |
| sing-box | `{"type": "socks", "listen": "127.0.0.1", "listen_port": 1080}` |
| SSH | `ssh -D 1080 -N user@server` |
| Shadowsocks | `ss-local -l 1080 -s server -p port -k password -m method` |
| gost | `gost -L socks5://127.0.0.1:1080 -F relay+tls://server:443` |

---

## Маскировка трафика

Переменная `MT_TLS_DOMAIN` — под какой сайт маскируется трафик. Провайдер видит обычный HTTPS к этому домену. Домен должен поддерживать TLS 1.3.

```
MT_TLS_DOMAIN=habr.com        # дефолт
MT_TLS_DOMAIN=www.google.com
MT_TLS_DOMAIN=yandex.ru
MT_TLS_DOMAIN=mail.ru
```

Рекомендуется популярный российский домен — трафик к нему не вызывает подозрений.

### Рекомендуемые порты

| Порт | Протокол | Шейпинг ТСПУ |
|---|---|---|
| `853` | DNS-over-TLS | Не шейпят — считают легитимным DNS |
| `443` | HTTPS | Не шейпят — стандартный HTTPS |
| `993` | IMAPS | Обычно не трогают |
| `465` | SMTPS | Обычно не трогают |
| `2443` | Нестандартный | **Шейпят** на мобильных операторах, задержка x10-x30 |
| `8443` | Нестандартный | **Шейпят**, задержка до 5 секунд |

Порт `853` — лучший выбор. Если он занят — `443` (но он часто занят xray/nginx). Портов `2443`, `8443` и подобных — избегать.

### Рекомендуемые VPS-провайдеры для РФ-ноды

Не все российские VPS работают одинаково. Некоторые провайдеры выдают IP из диапазонов, которые ТСПУ уже мониторит. Проверенные варианты:

| Провайдер | Ссылка | Комментарий |
|---|---|---|
| **Yandex Cloud** | [cloud.yandex.ru](https://cloud.yandex.ru/) | Стабильные IP, редко попадают под шейпинг |
| **VK Cloud** | [cloud.vk.com](https://cloud.vk.com/) | Хорошие IP-диапазоны |
| **EdgeCenter** | [edgecenter.ru](https://accounts.edgecenter.ru/dashboard) | Работает стабильно |

**Важно:** если прокси подключается и через секунду отваливается — IP скомпрометирован. ТСПУ детектирует MTProxy handshake и блокирует. Решение — сменить IP (новый VPS или переназначить IP у провайдера).

---

## Конфигурация

| Переменная | Дефолт | Описание |
|---|---|---|
| `MT_PORT` | `853` | Порт прокси |
| `MT_SECRET` | `auto` | Секрет. `auto` = новый при каждом старте |
| `MT_TLS_DOMAIN` | `habr.com` | Домен маскировки |
| `MT_CDN_IP` | `91.105.192.100` | IP CDN Telegram для видео |
| `MT_SOCKS5_HOST` | *(не задан)* | Адрес SOCKS5. Не задан = директ |
| `MT_SOCKS5_PORT` | *(не задан)* | Порт SOCKS5 |
| `MT_POOL_SIZE` | `5` | Готовых соединений в пуле |
| `MTPROXY_DEBUG` | `0` | `1` = подробные логи |

### Постоянная ссылка

При `MT_SECRET=auto` ссылка меняется при каждом перезапуске. Для постоянной:

```bash
# Сгенерировать секрет один раз
python3 -c "import secrets; print(secrets.token_hex(16))"
# Например: 7205fa45adefcc1809d4e8cb33132236

# Указать при установке
MT_SECRET=7205fa45adefcc1809d4e8cb33132236 sudo bash install.sh

# Или в docker-compose.yml
- MT_SECRET=7205fa45adefcc1809d4e8cb33132236
```

### Если видео не грузится

CDN IP различается по регионам. Дефолт `91.105.192.100` работает для РФ. Чтобы узнать свой:

**Android:** Telegram Beta → Настройки → Отладка → Экспорт логов → `grep "add.*dc203" *_net.txt`

**Desktop:** запустить с `-debug`, искать `dc203` в логах.

Задать: `MT_CDN_IP=найденный_ip`

---

## Что улучшено

- **Пул соединений** — 5 готовых подключений, клиент не ждёт handshake
- **TCP_NODELAY** — минус 40-200ms на мелких пакетах
- **Буферы 131KB-1MB** — быстрее фото и видео
- **Health checker** — мониторит SOCKS5, чистит пул при деградации
- **CDN fix** — конфигурируемый IP для DC 203, видео грузится
- **Рандомизированный TLS fingerprint** — GREASE, перемешанные cipher suites, неотличим от Chrome
- **Конфигурируемый домен маскировки** — `MT_TLS_DOMAIN`

---

## Отладка

```bash
# Нативная установка
journalctl -fu mtproxy
journalctl -u mtproxy | grep "dc=203"
journalctl -u mtproxy | grep -E "TIMEOUT|OSERROR|FAIL"

# Docker
docker logs -f mtproxy
docker logs mtproxy 2>&1 | grep "dc=203"
docker logs mtproxy 2>&1 | grep -E "TIMEOUT|OSERROR|FAIL"
```

| Проблема | Решение |
|---|---|
| Текст есть, видео нет | Определить CDN IP, задать `MT_CDN_IP` |
| Не подключается | Проверить порт: `ss -tlnp \| grep PORT`. Проверить firewall |
| `Connection refused` | SOCKS5 не запущен на указанном порту |
| Зависает | Добавить health check (ниже) |

### Автоматический перезапуск при зависании

```bash
cat > /usr/local/bin/mtproxy-health.sh << 'BASH'
#!/bin/bash
PORT=$(grep -oP 'PORT = \K\d+' /opt/mtproxy/config.py 2>/dev/null || echo 853)
if ! timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
    logger "mtproxy-health: not responding, restarting"
    systemctl restart mtproxy 2>/dev/null || docker restart mtproxy 2>/dev/null
fi
BASH
chmod +x /usr/local/bin/mtproxy-health.sh
(crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/mtproxy-health.sh") | sort -u | crontab -
```

---

## Лицензия

MIT
