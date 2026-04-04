#!/bin/bash
set -e

# ── Defaults ──
PORT="${MT_PORT:-853}"
TLS_DOMAIN="${MT_TLS_DOMAIN:-vkvideo.ru}"
SOCKS5_HOST="${MT_SOCKS5_HOST:-}"
SOCKS5_PORT="${MT_SOCKS5_PORT:-}"
CDN_IP="${MT_CDN_IP:-91.105.192.100}"
POOL_SIZE="${MT_POOL_SIZE:-5}"
FAST_MODE="${MT_FAST_MODE:-True}"

# ── Secret: use provided or generate new ──
if [ -n "$MT_SECRET" ] && [ "$MT_SECRET" != "auto" ]; then
    SECRET="$MT_SECRET"
else
    SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
fi

# ── Generate config ──
cat > /opt/mtproxy/config.py << PYEOF
PORT = ${PORT}
USERS = {"tg": "${SECRET}"}
MODES = {"classic": False, "secure": False, "tls": True}
TLS_DOMAIN = "${TLS_DOMAIN}"
MASK_HOST = "${TLS_DOMAIN}"
USE_MIDDLE_PROXY = False
FAST_MODE = ${FAST_MODE}
PREFER_IPV6 = False
TO_CLT_BUFSIZE = (131072, 50, 1048576)
TO_TG_BUFSIZE  = (131072, 50, 1048576)
TG_READ_TIMEOUT    = 300
CLIENT_KEEPALIVE   = 600
CLIENT_ACK_TIMEOUT = 900
TG_CONNECT_TIMEOUT = 15
POOL_SIZE = ${POOL_SIZE}
HEALTH_CHECK_INTERVAL = 30
HEALTH_CHECK_MAX_LATENCY = 3.0
CDN_DC_IPS = {203: "${CDN_IP}"}
PYEOF

# ── SOCKS5 (optional) ──
if [ -n "$SOCKS5_HOST" ] && [ -n "$SOCKS5_PORT" ]; then
    cat >> /opt/mtproxy/config.py << PYEOF
SOCKS5_HOST = "${SOCKS5_HOST}"
SOCKS5_PORT = ${SOCKS5_PORT}
PYEOF
    if [ -n "$MT_SOCKS5_USER" ]; then
        cat >> /opt/mtproxy/config.py << PYEOF
SOCKS5_USER = "${MT_SOCKS5_USER}"
SOCKS5_PASS = "${MT_SOCKS5_PASS}"
PYEOF
    fi
fi

# ── Backup SOCKS5 (optional) ──
if [ -n "$MT_SOCKS5_HOST_BACKUP" ]; then
    cat >> /opt/mtproxy/config.py << PYEOF
SOCKS5_HOST_BACKUP = "${MT_SOCKS5_HOST_BACKUP}"
SOCKS5_PORT_BACKUP = ${MT_SOCKS5_PORT_BACKUP}
PYEOF
fi

# ── Print info ──
TLS_SECRET="ee${SECRET}$(echo -n "${TLS_DOMAIN}" | xxd -p | tr -d '\n')"

echo "══════════════════════════════════════════"
echo "  MTProxy Patched — Docker"
echo "══════════════════════════════════════════"
echo "  Port:       ${PORT}"
echo "  Secret:     ${SECRET}"
echo "  TLS Domain: ${TLS_DOMAIN}"
echo "  CDN IP:     ${CDN_IP}"
[ -n "$SOCKS5_HOST" ] && echo "  SOCKS5:     ${SOCKS5_HOST}:${SOCKS5_PORT}"
echo ""
echo "  tg://proxy?server=YOUR_IP&port=${PORT}&secret=${TLS_SECRET}"
echo "══════════════════════════════════════════"

# ── Run ──
exec python3 -u /opt/mtproxy/mtproxy_patched.py /opt/mtproxy/config.py
