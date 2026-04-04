# mtproxy-patched

MTProxy-сервер для Telegram с поддержкой SOCKS5-туннелирования, фиксом загрузки видео и оптимизациями производительности.

Принимает подключения от Telegram-клиентов и заворачивает весь трафик в локальный SOCKS5 (`127.0.0.1:1080`). Что стоит за этим портом — xray, sing-box, SSH-туннель, WireGuard, Shadowsocks — прокси не знает и не заботится. Это позволяет менять транспорт до внешнего мира без перенастройки прокси и без перенастройки клиентов.

## Зачем

РКН блокирует Telegram несколькими способами одновременно:

- **Блокировка IP** — прямые адреса Telegram DC недоступны
- **DPI по протоколу** — ТСПУ распознаёт MTProto даже через obfuscation
- **Шейпинг** — соединения к известным прокси замедляются до непригодности

Стандартный MTProxy решает только первую проблему. Этот — все три: FakeTLS маскирует протокол под обычный HTTPS к указанному домену, а SOCKS5-туннель через промежуточный сервер обходит блокировку IP и шейпинг.

## Архитектура

```
┌─────────────────┐
│ Telegram-клиент │
│ (телефон/десктоп)│
└────────┬────────┘
         │ MTProto FakeTLS (провайдер видит HTTPS к MT_TLS_DOMAIN)
         ▼
┌─────────────────────────────────────────────┐
│              РФ-нода                         │
│                                              │
│  ┌──────────────────┐    ┌────────────────┐  │
│  │ MTProxy :PORT     │───▶│ SOCKS5 :1080   │  │
│  │ (этот контейнер)  │    │ (любой туннель)│  │
│  └──────────────────┘    └───────┬────────┘  │
│                                  │           │
└──────────────────────────────────┼───────────┘
                                   │ зашифрованный туннель
                                   ▼
                          ┌─────────────────┐
                          │   Внешний сервер │
                          │   (евро-нода,   │
                          │    VPS, любой)   │
                          └────────┬────────┘
                                   │ прямое TCP
                                   ▼
                          ┌─────────────────┐
                          │   Telegram DC    │
                          │  149.154.x.x    │
                          └─────────────────┘
```

MTProxy отвечает только за участок **клиент → SOCKS5**. Всё что дальше — ответственность туннеля. Это означает:

- **Можно менять туннель на лету** — переключить с xray на sing-box или SSH, перезапустить SOCKS5 на том же порту, MTProxy продолжит работать
- **Можно использовать любой протокол** — VLESS, VMess, Trojan, Shadowsocks, WireGuard (через tun2socks), обычный SSH (`ssh -D 1080`)
- **Можно менять внешний сервер** — перенаправить SOCKS5 outbound на другой VPS без перенастройки клиентов
- **Клиенты ничего не знают** — для Telegram-приложения это обычный MTProxy, одна ссылка `tg://proxy`

## Маскировка трафика

Параметр `MT_TLS_DOMAIN` определяет, под какой сайт маскируется трафик. Провайдер (и ТСПУ) видит обычный TLS-хендшейк к этому домену. Домен должен поддерживать TLS 1.3.

```bash
# Примеры доменов для маскировки
MT_TLS_DOMAIN=vkvideo.ru        # дефолт — VK Видео
MT_TLS_DOMAIN=www.google.com    # Google
MT_TLS_DOMAIN=yandex.ru         # Яндекс
MT_TLS_DOMAIN=mail.ru           # Mail.ru
MT_TLS_DOMAIN=habr.com          # Habr
```

Рекомендуется выбирать популярный российский домен — трафик к нему не вызывает подозрений у DPI.

## Совместимые туннели

Любой софт, который может поднять SOCKS5 inbound на `127.0.0.1:1080`:

| Туннель | Команда / конфиг |
|---|---|
| **xray / v2ray** | `"inbounds": [{"protocol": "socks", "port": 1080, "listen": "127.0.0.1"}]` |
| **sing-box** | `{"type": "socks", "listen": "127.0.0.1", "listen_port": 1080}` |
| **SSH** | `ssh -D 1080 -N user@server` |
| **Shadowsocks** | `ss-local -l 1080 -s server -p port -k password -m method` |
| **gost** | `gost -L socks5://127.0.0.1:1080 -F relay+tls://server:443` |

## Быстрый старт

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
      - MT_TLS_DOMAIN=vkvideo.ru
      - MT_SOCKS5_HOST=127.0.0.1
      - MT_SOCKS5_PORT=1080
EOF

ufw allow ${PORT}/tcp 2>/dev/null
docker compose -f /opt/mtproxy/docker-compose.yml up -d
sleep 3
IP=$(curl -4 -s ifconfig.me)
docker logs mtproxy 2>&1 | grep "tg://proxy" | grep "${IP}" | head -1
```

## Конфигурация

Все параметры задаются через переменные окружения в `docker-compose.yml`:

| Переменная | Дефолт | Описание |
|---|---|---|
| `MT_PORT` | `853` | Порт MTProxy |
| `MT_SECRET` | `auto` | Секрет. `auto` = новый при каждом старте. Для стабильной ссылки — 32 hex символа |
| `MT_TLS_DOMAIN` | `vkvideo.ru` | Домен для маскировки трафика. Провайдер видит HTTPS к этому домену |
| `MT_CDN_IP` | `91.105.192.100` | IP CDN Telegram (DC 203) для загрузки видео |
| `MT_SOCKS5_HOST` | `127.0.0.1` | Адрес SOCKS5 |
| `MT_SOCKS5_PORT` | `1080` | Порт SOCKS5 |
| `MT_POOL_SIZE` | `5` | Количество preconnect-соединений в пуле |
| `MT_FAST_MODE` | `True` | Сквозные ключи шифрования |
| `MTPROXY_DEBUG` | `0` | `1` = подробные логи |

### Стабильная ссылка

При `MT_SECRET=auto` секрет генерируется заново при каждом перезапуске — ссылка меняется. Для постоянной ссылки:

```bash
# Сгенерировать секрет один раз
python3 -c "import secrets; print(secrets.token_hex(16))"

# Задать в docker-compose.yml
environment:
  - MT_SECRET=7205fa45adefcc1809d4e8cb33132236
```

### Определение CDN IP

Дефолт `91.105.192.100` работает для большинства РФ-юзеров. Если видео не грузится:

**Android:** Telegram Beta → Настройки → Отладка → Экспорт логов → `grep "add.*dc203" *_net.txt`

**Desktop:** запустить с `-debug`, искать `dc203` в логах.

## Модификации

### Производительность
- **Connection pool с preconnect** — 5 готовых соединений через SOCKS5 вместо 0
- **TCP_NODELAY** — убирает задержку 40-200ms на всех сокетах
- **Буферы 131KB-1MB** — снижает syscall overhead для медиа
- **Адаптивный drain** — подстраивается под состояние канала

### Надёжность
- **SOCKS5 health checker** — мониторинг latency, авточистка пула при деградации
- **SOCKS5 failover** — поддержка backup SOCKS5 с race двух подключений
- **Per-session метрики** — `session=XXkB` в логах

### CDN / Видео
- **Конфигурируемый CDN IP** — `MT_CDN_IP` для правильной маршрутизации DC 203
- **FAST_MODE для CDN** — корректные сквозные ключи

### Маскировка
- **Рандомизированный TLS fingerprint** — GREASE, перемешанные cipher suites, неотличим от Chrome
- **Конфигурируемый домен** — `MT_TLS_DOMAIN` для выбора маскировки

## Отладка

```bash
docker logs -f mtproxy
docker logs mtproxy 2>&1 | grep "dc=203"
docker logs mtproxy 2>&1 | grep "SESSION_END.*session="
docker logs mtproxy 2>&1 | grep -E "TIMEOUT|OSERROR|FAIL"
```

### Типичные проблемы

| Симптом | Решение |
|---|---|
| Текст работает, видео нет | Определить CDN IP из логов клиента, задать `MT_CDN_IP` |
| Задержки растут | Health checker чистит пул автоматически. Проверить туннель |
| Клиент не подключается | Проверить firewall, сменить `MT_TLS_DOMAIN` |
| Контейнер падает | `ss -tlnp \| grep PORT` — порт занят другим сервисом |

## Структура

```
.
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── mtproxy_patched.py
├── .github/workflows/docker.yml
├── LICENSE
└── README.md
```

## Лицензия

MIT
