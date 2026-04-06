#!/usr/bin/env bash
# MTProxy Patched — нативная установка без Docker
# Usage: sudo bash install-native.sh [port] [tls_domain]
#
# Переменные окружения (опционально):
#   MT_PORT        (default: 853)
#   MT_SECRET      (default: auto)
#   MT_TLS_DOMAIN  (default: habr.com)
#   MT_CDN_IP      (default: 91.105.192.100)
#   MT_SOCKS5_HOST (default: none — директ-режим)
#   MT_SOCKS5_PORT (default: none)

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${CYAN}[..] $*${NC}"; }
warn() { echo -e "${YELLOW}[!!] $*${NC}"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Нужен root: sudo bash $0"

# ── Параметры ────────────────────────────────────────────────────────────────
PORT="${1:-${MT_PORT:-853}}"
TLS_DOMAIN="${2:-${MT_TLS_DOMAIN:-habr.com}}"
SECRET="${MT_SECRET:-auto}"
CDN_IP="${MT_CDN_IP:-91.105.192.100}"
SOCKS5_HOST="${MT_SOCKS5_HOST:-}"
SOCKS5_PORT="${MT_SOCKS5_PORT:-}"
POOL_SIZE="${MT_POOL_SIZE:-5}"

INSTALL_DIR="/opt/mtproxy"
PROXY_URL="https://raw.githubusercontent.com/cmzmozg/mtproxy-patched/main/mtproxy_patched.py"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║   MTProxy Patched — Native Installation ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Python ───────────────────────────────────────────────────────────────────
info "Проверяем Python..."
if ! command -v python3 &>/dev/null; then
    fail "Python 3 не установлен"
fi
PY_VER=$(python3 -c 'import sys; print("%d%d" % sys.version_info[:2])')
[[ $PY_VER -lt 37 ]] && fail "Нужен Python 3.7+, найден $(python3 --version)"
ok "$(python3 --version)"

# ── Системные пакеты ─────────────────────────────────────────────────────────
info "Устанавливаем системные пакеты..."
apt-get update -q 2>/dev/null || true
apt-get install -y -q \
    python3-pip python3-dev \
    build-essential libssl-dev libffi-dev \
    curl 2>/dev/null || fail "Не удалось установить базовые пакеты"
ok "Базовые пакеты установлены"

# ── Python зависимости ───────────────────────────────────────────────────────
info "Устанавливаем cryptography..."
pip3 install --quiet --break-system-packages cryptography 2>/dev/null || \
pip3 install --quiet cryptography 2>/dev/null || \
apt-get install -y -q python3-cryptography 2>/dev/null || \
fail "Не удалось установить cryptography"
ok "cryptography установлена"

info "Устанавливаем uvloop (опционально)..."
pip3 install --quiet --break-system-packages uvloop 2>/dev/null || \
pip3 install --quiet uvloop 2>/dev/null || \
apt-get install -y -q python3-uvloop 2>/dev/null || \
warn "uvloop не установлен (не критично)"

# ── Скачиваем proxy ──────────────────────────────────────────────────────────
info "Скачиваем mtproxy_patched.py..."
mkdir -p "$INSTALL_DIR"

if [[ -f "./mtproxy_patched.py" ]]; then
    cp ./mtproxy_patched.py "$INSTALL_DIR/mtproxy_patched.py"
    ok "Использован локальный mtproxy_patched.py"
else
    curl -sL "$PROXY_URL" -o "$INSTALL_DIR/mtproxy_patched.py" || \
        fail "Не удалось скачать mtproxy_patched.py"
    ok "Скачан с GitHub"
fi

chmod 755 "$INSTALL_DIR/mtproxy_patched.py"

# ── Пользователь ─────────────────────────────────────────────────────────────
id mtproxy &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin mtproxy
ok "Пользователь mtproxy готов"

# ── Секрет ───────────────────────────────────────────────────────────────────
if [[ "$SECRET" == "auto" ]]; then
    if [[ -f "$INSTALL_DIR/secret.txt" ]]; then
        SECRET=$(cat "$INSTALL_DIR/secret.txt")
        info "Загружен существующий секрет"
    else
        SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
        echo "$SECRET" > "$INSTALL_DIR/secret.txt"
        chmod 600 "$INSTALL_DIR/secret.txt"
        ok "Сгенерирован новый секрет"
    fi
else
    echo "$SECRET" > "$INSTALL_DIR/secret.txt"
    chmod 600 "$INSTALL_DIR/secret.txt"
    ok "Использован заданный секрет"
fi

# ── Конфиг ───────────────────────────────────────────────────────────────────
info "Создаём конфиг..."
cat > "$INSTALL_DIR/config.py" << PYEOF
PORT = ${PORT}
USERS = {"tg": "${SECRET}"}
MODES = {"classic": False, "secure": False, "tls": True}
TLS_DOMAIN = "${TLS_DOMAIN}"
MASK_HOST = "${TLS_DOMAIN}"
USE_MIDDLE_PROXY = False
FAST_MODE = True
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

# SOCKS5 (опционально)
if [[ -n "$SOCKS5_HOST" && -n "$SOCKS5_PORT" ]]; then
    cat >> "$INSTALL_DIR/config.py" << PYEOF
SOCKS5_HOST = "${SOCKS5_HOST}"
SOCKS5_PORT = ${SOCKS5_PORT}
PYEOF
    ok "Режим: SOCKS5 → ${SOCKS5_HOST}:${SOCKS5_PORT}"
else
    ok "Режим: директ (без SOCKS5)"
fi

chown -R mtproxy:mtproxy "$INSTALL_DIR"
chmod 640 "$INSTALL_DIR/config.py"
chown root:mtproxy "$INSTALL_DIR/config.py"

# ── Systemd unit ─────────────────────────────────────────────────────────────
info "Создаём systemd service..."
cat > /etc/systemd/system/mtproxy.service << 'UNIT'
[Unit]
Description=MTProxy Patched
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=mtproxy
Group=mtproxy
ExecStart=/usr/bin/python3 /opt/mtproxy/mtproxy_patched.py /opt/mtproxy/config.py
Environment="PYTHONUNBUFFERED=1"
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtproxy
LimitNOFILE=65536
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/opt/mtproxy
ProtectHome=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable mtproxy --quiet

# ── Firewall ─────────────────────────────────────────────────────────────────
info "Открываем порт ${PORT}..."
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow ${PORT}/tcp &>/dev/null && ok "ufw: ${PORT}/tcp открыт"
elif command -v iptables &>/dev/null; then
    iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT && ok "iptables: ${PORT}/tcp открыт"
fi

# ── Запуск ───────────────────────────────────────────────────────────────────
info "Запускаем mtproxy..."
systemctl restart mtproxy
sleep 2

if systemctl is-active --quiet mtproxy; then
    ok "mtproxy запущен"
else
    fail "mtproxy не запустился. Логи: journalctl -xe -u mtproxy"
fi

# ── Ссылка ───────────────────────────────────────────────────────────────────
IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "YOUR_IP")
TLS_SECRET="ee${SECRET}$(python3 -c "print('${TLS_DOMAIN}'.encode().hex())")"

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  MTProxy установлен и запущен${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  Порт:       ${PORT}"
echo -e "  Секрет:     ${SECRET}"
echo -e "  TLS Domain: ${TLS_DOMAIN}"
echo -e "  CDN IP:     ${CDN_IP}"
echo ""
echo -e "  ${CYAN}Ссылка для Telegram:${NC}"
echo -e "  ${GREEN}tg://proxy?server=${IP}&port=${PORT}&secret=${TLS_SECRET}${NC}"
echo ""
echo -e "  ${CYAN}Управление:${NC}"
echo -e "  systemctl status   mtproxy"
echo -e "  systemctl restart  mtproxy"
echo -e "  journalctl -fu     mtproxy"
echo ""
