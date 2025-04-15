#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Проверка установки AntiZapret-VPN
check_antizapret_installed() {
    if [ -d "$ANTIZAPRET_INSTALL_DIR" ]; then
        # Дополнительная проверка по наличию ключевых файлов
        if [ -f "$ANTIZAPRET_INSTALL_DIR/doall.sh" ] && [ -f "$ANTIZAPRET_INSTALL_DIR/ip.txt" ]; then
            return 0
        else
            log "Обнаружена неполная установка AntiZapret-VPN в $ANTIZAPRET_INSTALL_DIR"
            return 1
        fi
    else
        return 1
    fi
}

# Установка AntiZapret-VPN
install_antizapret() {
    log "Запуск установки AntiZapret-VPN"
    echo "${YELLOW}Установка AntiZapret-VPN...${NC}"

    # Проверка существующей установки
    if check_antizapret_installed; then
        echo "${YELLOW}AntiZapret-VPN уже установлен.${NC}"
        return 0
    fi

    # Скачивание и запуск установочного скрипта
    echo "${YELLOW}Скачивание установочного скрипта...${NC}"
    wget --no-hsts -qO /tmp/antizapret_install.sh "$ANTIZAPRET_INSTALL_SCRIPT"
    check_error "Не удалось скачать установочный скрипт"

    # Даем права на выполнение
    chmod +x /tmp/antizapret_install.sh

    # Запуск установки
    echo "${YELLOW}Запуск установки...${NC}"
    bash /tmp/antizapret_install.sh
    local install_status=$?

    # Проверка результата установки
    if [ $install_status -eq 0 ] && check_antizapret_installed; then
        log "AntiZapret-VPN успешно установлен"
        echo "${GREEN}AntiZapret-VPN успешно установлен!${NC}"
        
        # Установка прав для doall.sh
        chmod +x "$ANTIZAPRET_INSTALL_DIR/doall.sh"
        return 0
    else
        log "Ошибка при установке AntiZapret-VPN (код: $install_status)"
        echo "${RED}Ошибка при установке AntiZapret-VPN!${NC}"
        return 1
    fi
}

# Обновление AntiZapret-VPN
update_antizapret() {
    log "Запуск обновления AntiZapret-VPN"
    echo "${YELLOW}Обновление AntiZapret-VPN...${NC}"

    if ! check_antizapret_installed; then
        echo "${RED}AntiZapret-VPN не установлен!${NC}"
        return 1
    fi

    # Переходим в директорию с AntiZapret
    cd "$ANTIZAPRET_INSTALL_DIR" || return 1

    # Выполняем обновление
    ./doall.sh
    local update_status=$?

    if [ $update_status -eq 0 ]; then
        log "AntiZapret-VPN успешно обновлен"
        echo "${GREEN}AntiZapret-VPN успешно обновлен!${NC}"
        return 0
    else
        log "Ошибка при обновлении AntiZapret-VPN (код: $update_status)"
        echo "${RED}Ошибка при обновлении AntiZapret-VPN!${NC}"
        return 1
    fi
}

# Проверка статуса AntiZapret-VPN
check_antizapret_status() {
    echo "${YELLOW}Проверка статуса AntiZapret-VPN...${NC}"

    if ! check_antizapret_installed; then
        echo "${RED}AntiZapret-VPN не установлен!${NC}"
        return 1
    fi

    # Проверка активных VPN соединений
    echo -e "\n${GREEN}=== Активные VPN соединения ===${NC}"
    ip tunnel show | grep -E 'ipip|gre'

    # Проверка маршрутов
    echo -e "\n${GREEN}=== Маршруты VPN ===${NC}"
    ip route show table all | grep -i vpn | head -n 10

    # Проверка последних логов
    echo -e "\n${GREEN}=== Последние логи ===${NC}"
    tail -n 10 "$ANTIZAPRET_INSTALL_DIR/ip.txt"

    press_any_key
}

# Удаление AntiZapret-VPN
uninstall_antizapret() {
    log "Запуск удаления AntiZapret-VPN"
    echo "${YELLOW}Удаление AntiZapret-VPN...${NC}"

    if ! check_antizapret_installed; then
        echo "${YELLOW}AntiZapret-VPN не установлен.${NC}"
        return 0
    fi

    # Подтверждение удаления
    read -p "Вы уверены, что хотите удалить AntiZapret-VPN? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Удаление отменено.${NC}"
        return 0
    fi

    # Остановка всех VPN туннелей
    echo "${YELLOW}Остановка VPN туннелей...${NC}"
    for tun in $(ip tunnel show | grep -E 'ipip|gre' | awk '{print $2}'); do
        ip tunnel del "$tun"
    done

    # Удаление директории
    echo "${YELLOW}Удаление файлов...${NC}"
    rm -rf "$ANTIZAPRET_INSTALL_DIR"

    # Проверка результата
    if check_antizapret_installed; then
        log "Ошибка при удалении AntiZapret-VPN"
        echo "${RED}Не удалось полностью удалить AntiZapret-VPN!${NC}"
        return 1
    else
        log "AntiZapret-VPN успешно удален"
        echo "${GREEN}AntiZapret-VPN успешно удален!${NC}"
        return 0
    fi
}

# Меню управления AntiZapret-VPN
antizapret_menu() {
    while true; do
        clear
        echo "${GREEN}┌────────────────────────────────────────────┐"
        echo "│        Управление AntiZapret-VPN          │"
        echo "├────────────────────────────────────────────┤"
        echo "│ 1. Установить AntiZapret-VPN              │"
        echo "│ 2. Обновить AntiZapret-VPN                │"
        echo "│ 3. Проверить статус                       │"
        echo "│ 4. Удалить AntiZapret-VPN                 │"
        echo "│ 0. Назад                                  │"
        echo "└────────────────────────────────────────────┘${NC}"
        
        read -p "Выберите действие: " choice
        case $choice in
            1) install_antizapret; press_any_key ;;
            2) update_antizapret; press_any_key ;;
            3) check_antizapret_status ;;
            4) uninstall_antizapret; press_any_key ;;
            0) break ;;
            *) echo "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}