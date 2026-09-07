#!/bin/sh
set -e

# 0. Остановка процесса и очистка старой установки
echo "[+] Остановка и очистка предыдущей установки..."
killall -9 xkeen-ui 2>/dev/null || true
rm -f /opt/sbin/xkeen-ui /opt/etc/init.d/S99xkeen-ui

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

# 2. Скачивание во временный файл и перемещение в /opt/sbin
URL="https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-${BIN_ARCH}"
INSTALL_DIR="/opt/sbin"
TARGET_BIN="$INSTALL_DIR/xkeen-ui"
TMP_BIN="/tmp/xkeen-ui-download"

echo "[+] Скачивание бинарного файла для архитектуры ($BIN_ARCH)..."
mkdir -p "$INSTALL_DIR"
rm -f "$TMP_BIN"

curl -sSL "$URL" -o "$TMP_BIN"

if [ ! -s "$TMP_BIN" ]; then
    echo "[!] Ошибка: Не удалось скачать файл или скачанный файл пуст."
    rm -f "$TMP_BIN"
    exit 1
fi

mv "$TMP_BIN" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

# 3. Создание скрипта автозапуска в Entware
INIT_SCRIPT="/opt/etc/init.d/S99xkeen-ui"
echo "[+] Настройка автозапуска ($INIT_SCRIPT)..."

cat << 'INITEOT' > "$INIT_SCRIPT"
#!/bin/sh

case "$1" in
    start)
        if ! pidof xkeen-ui >/dev/null; then
            nohup /opt/sbin/xkeen-ui >/dev/null 2>&1 &
        fi
        ;;
    stop)
        killall -9 xkeen-ui 2>/dev/null
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
INITEOT

chmod +x "$INIT_SCRIPT"

# 4. Запуск утилиты
echo "[+] Запуск XKeen-UI..."
"$INIT_SCRIPT" restart >/dev/null 2>&1

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
