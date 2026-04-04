# mtproxy-patched

MTProxy-сервер для Telegram с поддержкой SOCKS5-туннелирования, фиксом загрузки видео и оптимизациями производительности.

Принимает подключения от Telegram-клиентов и заворачивает весь трафик в локальный SOCKS5 (`127.0.0.1:1080`). Что стоит за этим портом — xray, sing-box, SSH-туннель, WireGuard, Shadowsocks — прокси не знает и не заботится. Это позволяет менять транспорт до внешнего мира без перенастройки прокси и без перенастройки клиентов.

## Зачем

РКН блокирует Telegram несколькими способами одновременно:

- **Блокировка IP** — прямые адреса Telegram DC недоступны
- **DPI по протоколу** — ТСПУ распознаёт MTProto даже через obfuscation
- **Шейпинг** — соединения к известным прокси замедляются до непригодности

Стандартный MTProxy решает только первую проблему. Этот — все три: FakeTLS маскирует протокол под обычный HTTPS, а SOCKS5-туннель через промежуточный сервер обходит блокировку IP и шейпинг.

## Архитектура

```
┌─────────────────┐
│ Telegram-клиент │
│ (телефон/десктоп)│
└────────┬────────┘
         │ MTProto FakeTLS (выглядит как HTTPS к vkvideo.ru)
         ▼
┌─────────────────────────────────────────────┐
│              РФ-нода                         │
│                                              │
│  ┌──────────────────┐    ┌────────────────┐  │
│  │ MTProxy :853      │───▶│ SOCKS5 :1080   │  │
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

## Совместимые туннели

Любой софт, который может поднять SOCKS5 inbound на `127.0.0.1:1080`:

| Туннель | Команда / конфиг |
|---|---|
| **xray / v2ray** | `"inbounds": [{"protocol": "socks", "port": 1080, "listen": "127.0.0.1"}]` |
| **sing-box** | `{"type": "socks", "listen": "127.0.0.1", "listen_port": 1080}` |
| **SSH** | `ssh -D 1080 -N user@server` |
| **Shadowsocks** | `ss-local -l 1080 -s server -p port -k password -m method` |
| **Dante** | SOCKS5 сервер с upstream |
| **gost** | `gost -L socks5://127.0.0.1:1080 -F relay+tls://server:443` |

## Модификации относительно оригинального MTProxy

### Производительность

- **Connection pool с preconnect** — пул из 5 готовых соединений через SOCKS5. В оригинале при каждом подключении клиента прокси заново проходил SOCKS5 handshake + TLS + MTProto handshake к Telegram DC. Теперь соединения создаются заранее, клиент получает готовое из пула
- **TCP_NODELAY** — отключает алгоритм Nagle на всех сокетах (клиент, SOCKS5, Telegram). Убирает задержку 40-200ms на каждом мелком пакете — критично для интерактивного мессенджера
- **Увеличенные буферы** — 131KB-1MB вместо 16-128KB. Снижает количество системных вызовов при передаче фото и видео через SOCKS5 chain
- **Адаптивный drain** — автоматически подстраивает частоту flush под текущее состояние канала. При деградации реже дренажит (больше throughput), при хорошем канале — чаще (меньше latency)

### Надёжность

- **SOCKS5 health checker** — фоновая задача каждые 30 секунд проверяет latency через SOCKS5 к Telegram DC. Если задержка превышает порог — чистит connection pool, вынуждая создать свежие соединения. Логирует consecutive failures
- **SOCKS5 failover** — поддержка backup SOCKS5 сервера. При подключении пробует primary и backup параллельно, берёт первый ответивший
- **Per-session метрики** — `session=XXkB` в логах показывает реальный объём данных каждой сессии, а не кумулятивный счётчик юзера

### CDN / Видео (DC 203)

Telegram использует CDN-серверы (DC 203) для раздачи видео и тяжёлых файлов. IP этих серверов отличается от основных DC и различается по регионам. В оригинальном MTProxy захардкожен устаревший IP `149.154.167.99`, который для РФ-юзеров давно не актуален — реальный CDN IP `91.105.192.100` (получается через `getConfig` от Telegram).

- **Конфигурируемый CDN IP** — параметр `MT_CDN_IP` позволяет задать актуальный IP без пересборки
- **Корректный FAST_MODE для CDN** — сквозные ключи шифрования работают только при подключении к правильному IP. С неправильным IP Telegram молча дропает соединение (запросы уходят, ответы не приходят)

### Маскировка

- **Рандомизированный TLS ClientHello** — GREASE значения, перемешанные cipher suites и extensions, случайный padding. Оригинальный MTProxy генерировал фиксированный fingerprint, который ТСПУ научился детектировать и дропать. Новая версия неотличима от Chrome/Firefox/Safari

## Быстрый старт

### Из GitHub Container Registry

```bash
echo "GITHUB_TOKEN" | docker login ghcr.io -u ЮЗЕР --password-stdin

mkdir -p /opt/mtproxy && cat > /opt/mtproxy/docker-compose.yml << 'EOF'
services:
  mtproxy:
    image: ghcr.io/ЮЗЕР/mtproxy-patched:latest
    container_name: mtproxy
    restart: always
    network_mode: host
    environment:
      - MT_PORT=853
      - MT_SECRET=auto
      - MT_SOCKS5_HOST=127.0.0.1
      - MT_SOCKS5_PORT=1080
EOF

cd /opt/mtproxy && docker compose up -d

IP=$(curl -s ifconfig.me)
docker logs mtproxy 2>&1 | grep "tg://proxy" | sed "s/YOUR_IP/$IP/"
```

### Из исходников

```bash
git clone git@github.com:ЮЗЕР/mtproxy-patched.git
cd mtproxy-patched
docker compose up -d
```

## Конфигурация

Все параметры задаются через переменные окружения в `docker-compose.yml`:

| Переменная | Дефолт | Описание |
|---|---|---|
| `MT_PORT` | `853` | Порт MTProxy |
| `MT_SECRET` | `auto` | Секрет. `auto` = генерация при каждом старте. Для стабильной ссылки задать 32 hex символа |
| `MT_TLS_DOMAIN` | `vkvideo.ru` | Домен FakeTLS маскировки. Должен поддерживать TLS 1.3 |
| `MT_CDN_IP` | `91.105.192.100` | IP CDN Telegram (DC 203) для загрузки видео |
| `MT_SOCKS5_HOST` | `127.0.0.1` | Адрес SOCKS5 |
| `MT_SOCKS5_PORT` | `1080` | Порт SOCKS5 |
| `MT_POOL_SIZE` | `5` | Количество preconnect-соединений в пуле |
| `MT_FAST_MODE` | `True` | Сквозные ключи шифрования (быстрее, но требует правильный CDN IP) |
| `MTPROXY_DEBUG` | `0` | `1` = подробные логи для отладки |

### Стабильная ссылка

При `MT_SECRET=auto` секрет генерируется заново при каждом перезапуске контейнера — ссылка меняется. Чтобы ссылка оставалась постоянной:

```bash
# Сгенерировать секрет один раз
python3 -c "import secrets; print(secrets.token_hex(16))"
# Например: 7205fa45adefcc1809d4e8cb33132236

# Задать в docker-compose.yml
environment:
  - MT_SECRET=7205fa45adefcc1809d4e8cb33132236
```

### Определение CDN IP

Дефолт `91.105.192.100` работает для большинства РФ-юзеров. Если видео не грузится — нужно узнать IP своего CDN-сервера:

**Android:** Telegram Beta → Настройки → Отладка → Экспорт логов → в файле `*_net.txt`:
```bash
grep "add.*dc203" *_net.txt
# getConfig add 91.105.192.100:443 to dc203
```

**Desktop:** запустить с `-debug`, искать `dc203` в логах.

## Отладка

```bash
# Логи в реальном времени
docker logs -f mtproxy

# CDN-трафик (видео)
docker logs mtproxy 2>&1 | grep "dc=203"

# Объём данных per-session
docker logs mtproxy 2>&1 | grep "SESSION_END.*session="

# Ошибки
docker logs mtproxy 2>&1 | grep -E "TIMEOUT|OSERROR|FAIL|NO_TG_CONN"

# Health check SOCKS5
docker logs mtproxy 2>&1 | grep "HEALTH"
```

### Типичные проблемы

| Симптом | Причина | Решение |
|---|---|---|
| Текст работает, видео нет | Неправильный CDN IP | Определить IP из логов клиента, задать `MT_CDN_IP` |
| `session=0KB` для dc=203 | CDN не отвечает | Проверить CDN IP, проверить доступность через SOCKS5 |
| Задержки растут | Деградация туннеля | Health checker чистит пул автоматически. Проверить туннель |
| Клиент не подключается | Порт закрыт / TLS domain заблокирован | Проверить firewall, сменить `MT_TLS_DOMAIN` |
| Контейнер стартует и сразу падает | Порт занят | `ss -tlnp \| grep 853`, остановить конфликтующий сервис |

## Структура проекта

```
.
├── Dockerfile              # python:3.11-slim + cryptography + uvloop
├── docker-compose.yml      # Один контейнер, network_mode: host
├── entrypoint.sh           # Генерация config.py из env vars
├── mtproxy_patched.py      # Основной прокси (2734 строки)
├── .github/workflows/
│   └── docker.yml          # Автобилд → ghcr.io при push в main
├── .gitignore
├── .dockerignore
├── LICENSE
└── README.md
```

## Лицензия

MIT
