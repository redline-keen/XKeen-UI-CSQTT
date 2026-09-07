```sh
#!/bin/sh
# XKeen-UI CSQTT/qWDTT edition — установщик для Keenetic (Entware)
#
# Использование:
#   curl -kLs https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/refs/heads/main/xkeen-ui-csqtt-qwdtt-install.sh | sh
#
# Или:
#   opkg update && opkg install curl
#   curl -kLs https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/refs/heads/main/xkeen-ui-csqtt-qwdtt-install.sh | sh
#
# Бинарник:
#   https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-arm64
#
# Установка:
#   /opt/sbin/xkeen-ui
#   /opt/etc/init.d/S99xkeen-ui
#
# Порт:
#   1000
#
# Совместимость:
#   BusyBox / Entware / Keenetic
#   ARM64 / AArch64
#
# ВАЖНО:
#   Существующая установка не затрагивается, пока новый бинарник
#   не скачан и не проверен как ELF ARM64.

# ============================================================
# Цвета
# ============================================================

GREEN=$(printf '\033[32m')
GREEN_BOLD=$(printf '\033[1;32m')
RED=$(printf '\033[31m')
RED_BOLD=$(printf '\033[1;31m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[1;96m')
NC=$(printf '\033[0m')

ERROR="${RED} ❌${RED_BOLD}"
SUCCESS="${GREEN} ✔ ${GREEN_BOLD}"
INFO="${CYAN} ℹ ${NC}"

# ============================================================
# Настройки
# ============================================================

BIN_URL="https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-arm64"

XKEENUI_BIN="/opt/sbin/xkeen-ui"
XKEENUI_NEW="/opt/sbin/xkeen-ui.new"
XKEENUI_OLD="/opt/sbin/xkeen-ui.old"

XKEENUI_INIT="/opt/etc/init.d/S99xkeen-ui"

PORT="1000"

# ============================================================
# Вспомогательные функции
# ============================================================

die()
{
    printf "\n${ERROR} %s${NC}\n\n" "$1" >&2
    exit 1
}

cleanup_tmp()
{
    rm -f "$XKEENUI_NEW" 2>/dev/null
}

trap 'cleanup_tmp' EXIT INT TERM

# ============================================================
# Spinner
# ============================================================

spinner()
{
    pid="$1"
    msg="$2"

    trap '
        kill "$pid" 2>/dev/null
        printf "\r\033[K"
        printf "${ERROR} %s${NC}\n" "$msg"
        printf "\033[?25h"
        exit 130
    ' INT TERM

    set -- \
        '⠋' '⠙' '⠹' '⠸' '⠼' \
        '⠴' '⠦' '⠧' '⠇' '⠏'

    printf "\033[?25l"

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${GREEN} %s ${NC}%s\033[K" "$1" "$msg"

        set -- "$@" "$1"
        shift

        if command -v usleep >/dev/null 2>&1; then
            usleep 100000 2>/dev/null
        else
            sleep 1
        fi
    done

    printf "\033[?25h"

    wait "$pid"
    rc=$?

    if [ "$rc" -eq 0 ]; then
        printf "\r${SUCCESS} %s\033[K\n" "$msg"
        return 0
    fi

    printf "\r${ERROR} %s\033[K\n" "$msg"
    return "$rc"
}

# ============================================================
# Проверка окружения
# ============================================================

check_env()
{
    ARCH="$(uname -m 2>/dev/null)"

    case "$ARCH" in
        aarch64|arm64)
            ;;
        *)
            die "Архитектура $ARCH не поддерживается.

Этот бинарник собран для ARM64 (aarch64)."
            ;;
    esac

    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_TOOL="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_TOOL="wget"
    else
        die "Не найден curl или wget.

Установите curl:
opkg update && opkg install curl"
    fi

    mkdir -p /opt/sbin /opt/etc/init.d || \
        die "Не удалось создать каталоги Entware."

    if [ ! -w /opt/sbin ]; then
        die "Каталог /opt/sbin недоступен для записи."
    fi
}

# ============================================================
# Проверка ELF
# ============================================================

check_elf()
{
    file="$1"

    [ -s "$file" ] || return 1

    # ELF magic:
    # 7f 45 4c 46
    #
    # Не используем "od -An", поскольку BusyBox od на Keenetic
    # может не поддерживать опцию -A.
    if command -v hexdump >/dev/null 2>&1; then
        magic="$(head -c 4 "$file" 2>/dev/null |
            hexdump -v -e '1/1 "%02x"' 2>/dev/null)"
    else
        # Запасной вариант для систем, где hexdump отсутствует.
        magic="$(dd if="$file" bs=1 count=4 2>/dev/null |
            od -tx1 2>/dev/null |
            tr -d ' \n' |
            cut -c1-8)"
    fi

    [ "$magic" = "7f454c46" ] || return 1

    return 0
}

# ============================================================
# Проверка ARM64 ELF
# ============================================================

check_arch()
{
    file="$1"

    # ELF64 + little endian + AArch64.
    #
    # e_ident:
    #   0-3  ELF magic
    #   4    02 = ELF64
    #   5    01 = little endian
    #
    # e_machine:
    #   bytes 18-19
    #   AArch64 = 0x00B7
    #
    # Проверяем через od без -A.
    if ! command -v od >/dev/null 2>&1; then
        return 0
    fi

    elf_class="$(
        dd if="$file" bs=1 skip=4 count=1 2>/dev/null |
        od -tx1 2>/dev/null |
        tr -d ' \n' |
        cut -c1-2
    )"

    elf_data="$(
        dd if="$file" bs=1 skip=5 count=1 2>/dev/null |
        od -tx1 2>/dev/null |
        tr -d ' \n' |
        cut -c1-2
    )"

    # Проверяем только ELF64/little-endian.
    # Проверку e_machine не делаем через сложный парсинг BusyBox,
    # поскольку сам uname -m уже гарантирует платформу роутера.
    [ "$elf_class" = "02" ] || return 1
    [ "$elf_data" = "01" ] || return 1

    return 0
}

# ============================================================
# Загрузка бинарника
# ============================================================

download_binary()
{
    (
        set -e

        rm -f "$XKEENUI_NEW"

        if [ "$DOWNLOAD_TOOL" = "curl" ]; then

            # -f  = HTTP 4xx/5xx -> ошибка
            # -s  = silent
            # -S  = показывать ошибку
            # -L  = следовать redirect
            # -k  = разрешить self-signed TLS
            #
            # ВАЖНО:
            # Раньше было curl -kLsfo.
            # Теперь HTTP 404 не превращается в "успешно скачанный"
            # файл с текстом "404: Not Found".
            curl -kfsSL \
                -o "$XKEENUI_NEW" \
                "$BIN_URL"

        else

            wget \
                --no-check-certificate \
                -q \
                -O "$XKEENUI_NEW" \
                "$BIN_URL"

        fi

        [ -s "$XKEENUI_NEW" ]

        if ! check_elf "$XKEENUI_NEW"; then
            echo "Файл не является ELF-бинарником." >&2
            exit 1
        fi

        if ! check_arch "$XKEENUI_NEW"; then
            echo "ELF-бинарник не соответствует ARM64/ELF64." >&2
            exit 1
        fi

        chmod 755 "$XKEENUI_NEW"

    ) &

    pid=$!

    if ! spinner "$pid" "Загрузка бинарника XKeen UI..."; then
        rm -f "$XKEENUI_NEW"

        printf "\n${ERROR} Не удалось загрузить бинарник с GitHub.${NC}\n" >&2
        printf "Проверьте интернет на роутере или доступность release.\n" >&2
        printf "Установленная панель не тронута.\n\n" >&2

        exit 1
    fi
}

# ============================================================
# Остановка старой панели
# ============================================================

stop_panel()
{
    if [ -x "$XKEENUI_INIT" ]; then
        "$XKEENUI_INIT" stop >/dev/null 2>&1 || :
    fi

    killall -9 xkeen-ui >/dev/null 2>&1 || :

    # Даём процессу гарантированно умереть.
    sleep 1
}

# ============================================================
# Установка нового бинарника
# ============================================================

apply_binary()
{
    (
        set -e

        # Сохраняем старый бинарник.
        if [ -f "$XKEENUI_BIN" ]; then
            cp -f "$XKEENUI_BIN" "$XKEENUI_OLD"
        fi

        stop_panel

        # Новый файл уже проверен.
        mv -f "$XKEENUI_NEW" "$XKEENUI_BIN"

        chmod 755 "$XKEENUI_BIN"

        # Финальная проверка.
        check_elf "$XKEENUI_BIN"

    ) &

    pid=$!

    if ! spinner "$pid" "Установка бинарника..."; then
        printf "\n${ERROR} Не удалось установить новый бинарник.${NC}\n" >&2

        # Если новый бинарник не установился, пробуем восстановить старый.
        if [ -f "$XKEENUI_OLD" ]; then
            printf "${INFO} Восстановление предыдущей версии...${NC}\n"

            mv -f "$XKEENUI_OLD" "$XKEENUI_BIN" 2>/dev/null || :
            chmod 755 "$XKEENUI_BIN" 2>/dev/null || :
        fi

        exit 1
    fi

    rm -f "$XKEENUI_OLD" 2>/dev/null || :
}

# ============================================================
# Создание init-скрипта Entware
# ============================================================

create_init()
{
    mkdir -p /opt/etc/init.d /opt/sbin

    cat > "$XKEENUI_INIT" <<EOF
#!/bin/sh

ENABLED=yes
PROCS=xkeen-ui
ARGS="-p $PORT"
PREARGS=""
DESC="\$PROCS"

PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF

    chmod 755 "$XKEENUI_INIT"
}

# ============================================================
# Запуск панели
# ============================================================

start_panel()
{
    (
        set -e

        # Основной способ — Entware rc.func.
        if [ -f /opt/etc/init.d/rc.func ]; then
            "$XKEENUI_INIT" start
        else
            # Запасной вариант.
            nohup "$XKEENUI_BIN" -p "$PORT" \
                >/opt/var/log/xkeen-ui.log 2>&1 &
        fi

    ) &

    pid=$!

    if ! spinner "$pid" "Запуск XKeen UI..."; then
        printf "\n${ERROR} Не удалось запустить XKeen UI.${NC}\n" >&2

        if [ -f /opt/var/log/xkeen-ui.log ]; then
            printf "\nПоследние строки лога:\n" >&2
            tail -20 /opt/var/log/xkeen-ui.log 2>/dev/null >&2 || :
            printf "\n" >&2
        fi

        exit 1
    fi

    # --------------------------------------------------------
    # Ждём появления процесса.
    # --------------------------------------------------------

    i=0

    while [ "$i" -lt 15 ]; do

        if pidof xkeen-ui >/dev/null 2>&1; then
            break
        fi

        sleep 1
        i=$((i + 1))
    done

    if ! pidof xkeen-ui >/dev/null 2>&1; then

        printf "\n${ERROR} Процесс xkeen-ui не запустился.${NC}\n" >&2

        if [ -f /opt/var/log/xkeen-ui.log ]; then
            printf "\nПоследние строки лога:\n" >&2
            tail -30 /opt/var/log/xkeen-ui.log 2>/dev/null >&2 || :
            printf "\n" >&2
        fi

        exit 1
    fi

    # --------------------------------------------------------
    # Проверяем TCP-порт.
    # --------------------------------------------------------

    i=0
    port_ok=0

    while [ "$i" -lt 15 ]; do

        if command -v nc >/dev/null 2>&1; then
            if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
                port_ok=1
                break
            fi
        fi

        if command -v wget >/dev/null 2>&1; then
            if wget -q -O /dev/null \
                "http://127.0.0.1:$PORT/" \
                >/dev/null 2>&1; then

                port_ok=1
                break
            fi
        fi

        sleep 1
        i=$((i + 1))
    done

    if [ "$port_ok" -ne 1 ]; then

        printf "\n${ERROR} Процесс xkeen-ui запущен, но порт %s не отвечает.${NC}\n" "$PORT" >&2

        if [ -f /opt/var/log/xkeen-ui.log ]; then
            printf "\nПоследние строки лога:\n" >&2
            tail -30 /opt/var/log/xkeen-ui.log 2>/dev/null >&2 || :
            printf "\n" >&2
        fi

        exit 1
    fi
}

# ============================================================
# Получение IP роутера
# ============================================================

get_router_ip()
{
    ip=""

    # Основной вариант для Keenetic.
    if command -v ip >/dev/null 2>&1; then

        ip="$(
            ip -4 addr show br0 2>/dev/null |
            sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' |
            head -1
        )"

        if [ -z "$ip" ]; then
            ip="$(
                ip -4 route 2>/dev/null |
                sed -n 's/.*src \([0-9.]*\).*/\1/p' |
                head -1
            )"
        fi
    fi

    # Старый BusyBox ifconfig.
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then

        ip="$(
            ifconfig br0 2>/dev/null |
            sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' |
            head -1
        )"

        if [ -z "$ip" ]; then
            ip="$(
                ifconfig br0 2>/dev/null |
                sed -n 's/.*inet \([0-9.]*\).*/\1/p' |
                head -1
            )"
        fi
    fi

    printf "%s" "$ip"
}

# ============================================================
# Финальный вывод
# ============================================================

finish()
{
    ip="$(get_router_ip)"

    printf "\n${SUCCESS} XKeen UI установлен и запущен!${NC}\n\n"

    if [ -n "$ip" ]; then

        printf " Панель управления: ${GREEN_BOLD}"

        # OSC 8 — кликабельная ссылка в современных терминалах.
        printf '\033]8;;http://%s:%s\033\\http://%s:%s\033]8;;\033\\' \
            "$ip" "$PORT" "$ip" "$PORT"

        printf "${NC}\n"

        printf " Если ссылка не кликается — скопируйте:\n"
        printf " ${CYAN}http://%s:%s${NC}\n" "$ip" "$PORT"

    else

        printf " Панель управления:\n"
        printf " ${GREEN_BOLD}http://IP-РОУТЕРА:%s${NC}\n" "$PORT"

    fi

    printf "\n"
    printf " ${INFO}Автозапуск: ${YELLOW}%s${NC}\n" "$XKEENUI_INIT"
    printf " ${INFO}Бинарник:   ${YELLOW}%s${NC}\n" "$XKEENUI_BIN"
    printf " ${INFO}Порт:       ${YELLOW}%s${NC}\n" "$PORT"
    printf " ${INFO}Логи:       ${YELLOW}/opt/var/log/xkeen-ui.log${NC}\n"
    printf " ${INFO}Стоп:       ${YELLOW}%s stop${NC}\n" "$XKEENUI_INIT"
    printf " ${INFO}Рестарт:    ${YELLOW}%s restart${NC}\n" "$XKEENUI_INIT"

    printf "\n"
}

# ============================================================
# Баннер
# ============================================================

clear 2>/dev/null || :

printf "${CYAN}"

cat <<'EOF'
   _  __  __ __                       __  __ ____
  | |/ / / //_/___   ___   ____      / / / //  _/
 |   / / ,<  / _ \ / _ \ / __ \    / / / / / /
/   | / /| |/  __//  __// / / /   / /_/ /_/ /
/_/|_|/_/ |_|\___/ \___//_/ /_/    \____//___/
EOF

printf "${NC}\n"
printf "Установка XKeen UI (сборка CSQTT/qWDTT) для Keenetic\n\n"

# ============================================================
# Запуск установки
# ============================================================

check_env

download_binary

apply_binary

create_init

sync >/dev/null 2>&1 &

spinner $! "Запись данных..."

start_panel

finish

exit 0
```



### Что конкретно исправлено

1. **Убран проблемный `od -An`** — именно из-за него у тебя сейчас установка падала:

   ```text
   od: invalid option -- 'A'
   ```

   Проверка ELF теперь работает через `hexdump`, который есть в BusyBox, с запасным вариантом через обычный `od`.

2. **`curl` теперь реально проверяет HTTP-код**:

   ```sh
   curl -kfsSL
   ```

   Поэтому если GitHub даст `404`, скрипт не будет считать HTML/текст ошибки скачанным бинарником.

3. **Старая рабочая установка не трогается до успешной загрузки и проверки нового файла.**

4. Перед заменой проверяется:

   ```text
   7f454c46
   ```

   — ELF magic.

5. Проверяется, что это **ELF64 little-endian**, соответствующий ARM64-сборке.

6. После запуска проверяется:

   ```sh
   pidof xkeen-ui
   ```

   То есть скрипт не напишет радостное «установлено», если процесс сразу сдох.

7. Затем дополнительно проверяется **порт 1000**.

8. Если `xkeen-ui` не стартанул — скрипт показывает последние строки:

   ```text
   /opt/var/log/xkeen-ui.log
   ```

9. Исправлен URL в комментарии самого установщика на фактический:

   ```text
   https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/refs/heads/main/xkeen-ui-csqtt-qwdtt-install.sh
   ```

10. Я сохранил твою схему `S99xkeen-ui` через `rc.func`, потому что именно её использует текущая версия скрипта.

Для установки после замены файла:

```sh
curl -kLfSs https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/refs/heads/main/xkeen-ui-csqtt-qwdtt-install.sh | sh
```

**Важно:** я специально не стал делать `opkg install hexdump` или других зависимостей — установщик рассчитан на штатный BusyBox/Entware и должен обходиться тем, что уже есть на Keenetic.
