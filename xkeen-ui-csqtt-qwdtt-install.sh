#!/bin/sh
set -e

# 1. Определение архитектуры процессора
ARCH=$(uname -m)
case "$ARCH" in
    mips|mipsel)
        BIN_ARCH="mipsle"
        ;;
    aarch64|arm64)
        BIN_ARCH="arm64"
        ;;
    armv7l|arm)
        BIN_ARCH="armv7"
        ;;
    x86_64)
        BIN_ARCH="amd64"
        ;;
    *)
        echo "[!] Неподдерживаемая архитектура: $ARCH"
        exit 1
        ;;
esac

# 2. Настройка путей и загрузка бинарника в /opt/sbin
URL="https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-${BIN_ARCH}"
INSTALL_DIR="/opt/sbin"
TARGET_BIN="$INSTALL_DIR/xkeen-ui"

echo "[+] Скачивание бинарного файла для архитектуры ($BIN_ARCH)..."
mkdir -p "$INSTALL_DIR"
curl -sSL "$URL" -o "$TARGET_BIN"

if [ ! -s "$TARGET_BIN" ]; then
    echo "[!] Ошибка: Не удалось скачать файл или скачанный файл пуст."
    rm -f "$TARGET_BIN"
    exit 1
fi

chmod +x "$TARGET_BIN"

# 3. Создание скрипта автозапуска в Entware
INIT_SCRIPT="/opt/etc/init.d/S99xkeen-ui"
echo "[+] Настройка автозапуска ($INIT_SCRIPT)..."

cat << 'INITEOT' > "$INIT_SCRIPT"
#!/bin/sh

ENABLED=yes
PROG=/opt/sbin/xkeen-ui
ARGS=""
PREARGS=""
DESC=$PROG
PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
INITEOT

chmod +x "$INIT_SCRIPT"

# 4. Запуск утилиты
echo "[+] Запуск XKeen-UI..."
"$INIT_SCRIPT" restart >/dev/null 2>&1 || "$TARGET_BIN" &

# 5. Определение IP роутера и вывод информации
ROUTER_IP=$(ip addr show br0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$ROUTER_IP" ]; then
    ROUTER_IP=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -n1)
fi
if [ -z "$ROUTER_IP" ]; then
    ROUTER_IP="192.168.1.1"
fi

PORT=1000

echo ""
echo "=================================================="
echo "  [✓] Установка и запуск успешно завершены!"
echo "=================================================="
echo "  Веб-интерфейс доступен по адресу:"
echo "  http://${ROUTER_IP}:${PORT}"
echo "=================================================="
echo ""
