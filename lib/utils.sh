#!/bin/bash

source ./lib/config.sh

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_error() {
    if [ $? -ne 0 ]; then
        log "Ошибка при выполнении: $1"
        printf "%s\n" "${RED}Ошибка при выполнении: $1${NC}" >&2
        exit 1
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "Попытка запуска без прав root"
        printf "%s\n" "${RED}Этот скрипт должен быть запущен с правами root!${NC}" >&2
        exit 1
    fi
}

press_any_key() {
    printf "\n%s\n" "${YELLOW}Нажмите любую клавишу чтобы продолжить...${NC}"
    read -r _
}

check_port() {
    port=$1
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            return 0
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i :$port >/dev/null; then
            return 0
        fi
    elif grep -q ":$port " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
        return 0
    else
        printf "%s\n" "${YELLOW}Не удалось проверить порт (установите ss, netstat или lsof для точной проверки)${NC}"
        return 1
    fi
    return 1
}