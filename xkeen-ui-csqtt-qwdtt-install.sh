#!/bin/sh
# XKeen-UI CSQTT edition — одноразовый установщик для Keenetic (Entware)
# Использование: curl -kLs https://raw.githubusercontent.com/redline-keen/XKeen-UI-CSQTT/main/install-xkeen-ui.sh | sh
#  или: opkg update && opkg install curl && curl ... | sh
# Скрипт: скачивает бинарь с GitHub → /opt/sbin/xkeen-ui, создаёт автозапуск
# S99xkeen-ui, запускает панель и печатает кликабельный адрес.

# Цвета через printf: $'...' — не POSIX и не работает в dash
GREEN=$(printf '\033[32m')
GREEN_BOLD=$(printf '\033[1;32m')
RED=$(printf '\033[31m')
RED_BOLD=$(printf '\033[1;31m')
NC=$(printf '\033[0m')
NCN="$NC\n\n"
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[1;96m')

ERROR="\n${RED} ❌${RED_BOLD}"
SUCCESS="\n${GREEN} ✅${GREEN_BOLD}"
INFO="${CYAN} ℹ️ ${NC}"

BIN_URL="https://github.com/redline-keen/XKeen-UI-CSQTT/releases/download/1.0/xkeen-ui-arm64"
XKEENUI_BIN="/opt/sbin/xkeen-ui"
XKEENUI_INIT="/opt/etc/init.d/S99xkeen-ui"
PORT="1000"

spinner() {
  pid=$1; msg=$2
  trap 'kill "$pid" 2>/dev/null; printf "\r${RED} ❌ ${NC}%s\033[K\n" "$msg"; printf "\033[?25h"; exit 130' INT
  set -- ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
  printf "\033[?25l"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${GREEN} %s ${NC} %s\033[K" "$1" "$msg"
    set -- "$@" "$1"
    shift
    # Entware busybox умеет usleep; в остальных шеллах паузим на секунду
    usleep 100000 2>/dev/null || sleep 1
  done
  printf "\033[?25h"
  wait "$pid" && printf "\r ✔  %s\033[K\n" "$msg" || { printf "\r ❌ %s\033[K\n" "$msg"; return 1; }
}

check_env() {
  # Скрипт не интерактивен, поэтому спокойно запускается через curl | sh
  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) printf "${ERROR} Архитектура $(uname -m) не поддерживается: бинарь собран для arm64 (aarch64).${NCN}" >&2; exit 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
    printf "${ERROR} Не найден curl или wget. Установите: opkg update && opkg install curl${NCN}" >&2
    exit 1
  }
}

download_binary() {
  (
    set -e
    tmp="$XKEENUI_BIN.new"
    if command -v curl >/dev/null 2>&1; then
      curl -kLsfo "$tmp" "$BIN_URL"
    else
      wget --no-check-certificate -qO "$tmp" "$BIN_URL"
    fi
    # Защита от HTML-страницы ошибки вместо бинарника: первые 4 байта — ELF-магия
    magic=$(head -c 4 "$tmp" | od -An -tx1 | tr -d ' \n')
    [ "$magic" = "7f454c46" ] || exit 1
  ) &
  if ! spinner $! "Загрузка бинарника XKeen UI..."; then
    rm -f "$XKEENUI_BIN.new"
    printf "${ERROR} Не удалось загрузить бинарник с GitHub.\nПроверьте интернет на роутере или повторите позже.\nУстановенная панель не тронута.${NCN}" >&2
    exit 1
  fi
}

apply_binary() {
  # Загрузка прошла — только теперь останавливаем прежнюю версию и подменяем бинарь
  (
    if [ -f "$XKEENUI_INIT" ]; then
      "$XKEENUI_INIT" stop >/dev/null 2>&1 || :
    fi
    killall -q -9 xkeen-ui 2>/dev/null || :
    mv -f "$XKEENUI_BIN.new" "$XKEENUI_BIN"
    chmod 755 "$XKEENUI_BIN"
  ) &
  if ! spinner $! "Замена бинарника..."; then
    printf "${ERROR} Не удалось заменить бинарник.${NCN}" >&2
    exit 1
  fi
}

create_init() {
  mkdir -p /opt/etc/init.d /opt/sbin
  cat << EOF > "$XKEENUI_INIT"
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

start_panel() {
  # автозапуск; при отсутствии rc.func (не Entware) — прямой запуск
  ("$XKEENUI_INIT" start >/dev/null 2>&1 || "$XKEENUI_BIN" -p "$PORT" >/dev/null 2>&1 &) &
  if ! spinner $! "Запуск XKeen UI..."; then
    printf "${ERROR} Панель не запустилась. Смотрите лог: cat /opt/var/log/xkeen-ui.log${NCN}" >&2
    exit 1
  fi
  # Дожидаемся, пока порт начнет отвечать (до 15с)
  i=0
  while [ $i -lt 15 ]; do
    if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then break; fi
    if wget -q -O /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then break; fi
    sleep 1
    i=$((i+1))
  done
}

finish() {
  ip=$(ip -4 a s br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
  [ -n "$ip" ] || ip=$(ip -4 route 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  [ -n "$ip" ] || ip=$(ifconfig br0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1)

  printf "${SUCCESS} XKeen UI установлен и запущен!${NCN}"
  if [ -n "$ip" ]; then
    printf " Панель управления: ${GREEN_BOLD}"
    # OSC 8 — кликабельная ссылка в любом современном терминале
    printf '\033]8;;http://%s:%s\033\\http://%s:%s\033]8;;\033\\' "$ip" "$PORT" "$ip" "$PORT"
    printf "${NC}\n"
    printf " Если ссылка не кликается — скопируйте адрес: ${CYAN}http://%s:%s${NC}\n" "$ip" "$PORT"
  else
    printf " Панель управления: ${GREEN_BOLD}http://IP_РОУТЕРА:%s${NC}\n" "$PORT"
  fi
  printf "\n ${CYAN}ℹ️ ${NC}Автозапуск: ${YELLOW}$XKEENUI_INIT${NC}\n"
  printf " ${CYAN}ℹ️ ${NC}Логи панели:   ${YELLOW}/opt/var/log/xkeen-ui.log${NC}\n"
  printf " ${CYAN}ℹ️ ${NC}Остановка:    ${YELLOW}$XKEENUI_INIT stop${NC}\n\n"
}

clear 2>/dev/null || :
printf "${CYAN}"
cat <<'EOF'
   _  __  __ __                       __  __ ____
  | |/ / / //_/___   ___   ____      / / / //  _/
 |   / / ,<  / _ \ / _ \ / __ \    / / / / / /
/   | / /| |/  __//  __// / / /   / /_/ /_/ /
/_/|_|/_/ |_|\___/ \___//_/ /_/    \____//___/
EOF
printf "${NC}"
printf "Установка XKeen UI (сборка CSQTT/qWDTT) для Keenetic\n\n"

check_env
download_binary
apply_binary
create_init
sync &
spinner $! "Запись данных..."
start_panel
finish
