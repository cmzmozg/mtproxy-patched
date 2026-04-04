# mtproxy-patched

MTProxy для Telegram с SOCKS5-туннелированием, CDN-фиксом и оптимизациями.

## Схема

```
Telegram-клиент
  → MTProxy :853 (FakeTLS → vkvideo.ru)
  → xray SOCKS5 :1080 (127.0.0.1)
  → chain-to-euro → Telegram DC
```

## Деплой

```bash
docker compose up -d
IP=$(curl -s ifconfig.me)
docker logs mtproxy 2>&1 | grep "tg://proxy" | sed "s/YOUR_IP/$IP/"
```

## Конфигурация

| Переменная | Дефолт | Описание |
|---|---|---|
| `MT_PORT` | `853` | Порт |
| `MT_SECRET` | `auto` | Секрет (auto = новый при каждом старте) |
| `MT_TLS_DOMAIN` | `vkvideo.ru` | Домен FakeTLS |
| `MT_CDN_IP` | `91.105.192.100` | IP CDN Telegram (DC 203, видео) |
| `MT_SOCKS5_HOST` | `127.0.0.1` | SOCKS5 адрес |
| `MT_SOCKS5_PORT` | `1080` | SOCKS5 порт |
| `MT_POOL_SIZE` | `5` | Preconnect-соединений |

## Модификации

- Connection pool с preconnect через SOCKS5
- TCP_NODELAY на всех сокетах
- Буферы 131KB-1MB
- Адаптивный drain
- SOCKS5 health checker
- CDN DC fix (DC 203 → правильный IP)
- Рандомизированный TLS fingerprint
- Per-session метрики

## Отладка

```bash
docker logs -f mtproxy
docker logs mtproxy 2>&1 | grep "dc=203"
docker logs mtproxy 2>&1 | grep -E "TIMEOUT|OSERROR|FAIL"
```

## Лицензия

MIT
