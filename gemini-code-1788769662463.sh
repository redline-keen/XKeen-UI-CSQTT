sh -c '$(wget -qO- https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/main/install.sh 2>/dev/null || cat << "EOF"
#!/bin/sh
set -e

# 1. Проверка наличия Entware (/opt)
if [ ! -d "/opt/bin" ] && [ ! -d "/opt/usr/bin" ]; then
    echo "[!] Ошибка: Entware не установлен на роутере."
    echo "[!] Установите Entware через компоненты Keenetic перед продолжением."
    exit 1
fi

# 2. Обновление пакетов и установка curl, если его нет
if ! command -v curl >/dev/null 2>&1; then
    echo "[+] curl не найден. Обновляем списки пакетов и устанавливаем curl..."
    opkg update
    opkg install curl ca-certificates
fi

# 3. Определение архитектуры процессора
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

# 4. Настройка путей и загрузка
URL="https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-1.0-${BIN_ARCH}.tar.gz"
TMP_DIR="/tmp/xkeen-ui-install"
INSTALL_DIR="/opt/etc/xkeen-ui"

echo "[+] Скачивание релиза для архитектуры ($BIN_ARCH)..."
mkdir -p "$TMP_DIR"
curl -sSL "$URL" -o "$TMP_DIR/xkeen-ui.tar.gz"

if [ ! -s "$TMP_DIR/xkeen-ui.tar.gz" ]; then
    echo "[!] Ошибка: Не удалось скачать файл или архив пуст."
    rm -rf "$TMP_DIR"
    exit 1
fi

# 5. Распаковка и установка
echo "[+] Распаковка архива..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP_DIR/xkeen-ui.tar.gz" -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/xkeen-ui" "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || chmod +x "$INSTALL_DIR/"*

# 6. Очистка временных файлов
rm -rf "$TMP_DIR"

echo "[✓] Установка завершена!"
echo "[i] Запустить бинарник можно командой: $INSTALL_DIR/xkeen-ui"
EOF
)'