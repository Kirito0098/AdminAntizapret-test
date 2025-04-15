#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Функция меню управления сервисом
service_management_menu() {
    while true; do
        clear
        echo "${GREEN}┌────────────────────────────────────────────┐"
        echo "│        Управление сервисом $SERVICE_NAME      │"
        echo "├────────────────────────────────────────────┤"
        echo "│ 1. Запустить сервис                       │"
        echo "│ 2. Остановить сервис                      │"
        echo "│ 3. Перезапустить сервис                   │"
        echo "│ 4. Проверить статус                       │"
        echo "│ 5. Просмотреть логи                       │"
        echo "│ 6. Включить автозагрузку                  │"
        echo "│ 7. Отключить автозагрузку                 │"
        echo "│ 8. Проверить конфигурацию                 │"
        echo "│ 0. Назад                                  │"
        echo "└────────────────────────────────────────────┘${NC}"
        
        read -p "Выберите действие: " choice
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) check_status ;;
            5) show_logs ;;
            6) enable_service ;;
            7) disable_service ;;
            8) check_service_config ;;
            0) break ;;
            *) echo "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Перезапуск сервиса
restart_service() {
    log "Перезапуск сервиса $SERVICE_NAME"
    echo "${YELLOW}Перезапуск сервиса $SERVICE_NAME...${NC}"
    
    systemctl restart "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        log "Сервис $SERVICE_NAME успешно перезапущен"
        echo "${GREEN}Сервис успешно перезапущен!${NC}"
    else
        log "Ошибка при перезапуске сервиса $SERVICE_NAME"
        echo "${RED}Ошибка при перезапуске сервиса!${NC}"
    fi
    
    check_status
}

# Проверка статуса сервиса
check_status() {
    log "Проверка статуса сервиса $SERVICE_NAME"
    echo "${YELLOW}Статус сервиса $SERVICE_NAME:${NC}"
    
    local status=$(systemctl is-active "$SERVICE_NAME")
    local color=$GREEN
    
    if [ "$status" != "active" ]; then
        color=$RED
    fi
    
    echo -n "Состояние: ${color}$status${NC} | "
    
    # Добавляем информацию о последних изменениях
    local since=$(systemctl show -p ActiveEnterTimestamp --value "$SERVICE_NAME")
    if [ -n "$since" ]; then
        echo "Активен с: $(date -d "$since" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Не активен"
    fi
    
    # Выводим последние 5 строк журнала
    echo -e "\n${YELLOW}Последние записи в журнале:${NC}"
    journalctl -u "$SERVICE_NAME" -n 5 --no-pager --no-hostname
    
    press_any_key
}

# Просмотр логов сервиса
show_logs() {
    log "Просмотр логов сервиса $SERVICE_NAME"
    echo "${YELLOW}Последние логи сервиса $SERVICE_NAME (Ctrl+C для выхода):${NC}"
    
    # Показываем последние 50 записей и продолжаем следить
    journalctl -u "$SERVICE_NAME" -n 50 -f --no-hostname
}

# Включение сервиса
enable_service() {
    log "Включение автозагрузки сервиса $SERVICE_NAME"
    echo "${YELLOW}Включение автозагрузки сервиса $SERVICE_NAME...${NC}"
    
    systemctl enable "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        log "Автозагрузка сервиса $SERVICE_NAME включена"
        echo "${GREEN}Автозагрузка сервиса включена!${NC}"
    else
        log "Ошибка при включении автозагрузки сервиса $SERVICE_NAME"
        echo "${RED}Ошибка при включении автозагрузки сервиса!${NC}"
    fi
    
    check_status
}

# Отключение сервиса
disable_service() {
    log "Отключение автозагрузки сервиса $SERVICE_NAME"
    echo "${YELLOW}Отключение автозагрузки сервиса $SERVICE_NAME...${NC}"
    
    systemctl disable "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        log "Автозагрузка сервиса $SERVICE_NAME отключена"
        echo "${GREEN}Автозагрузка сервиса отключена!${NC}"
    else
        log "Ошибка при отключении автозагрузки сервиса $SERVICE_NAME"
        echo "${RED}Ошибка при отключении автозагрузки сервиса!${NC}"
    fi
    
    check_status
}

# Запуск сервиса
start_service() {
    log "Запуск сервиса $SERVICE_NAME"
    echo "${YELLOW}Запуск сервиса $SERVICE_NAME...${NC}"
    
    systemctl start "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        log "Сервис $SERVICE_NAME успешно запущен"
        echo "${GREEN}Сервис успешно запущен!${NC}"
    else
        log "Ошибка при запуске сервиса $SERVICE_NAME"
        echo "${RED}Ошибка при запуске сервиса!${NC}"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
    fi
    
    check_status
}

# Остановка сервиса
stop_service() {
    log "Остановка сервиса $SERVICE_NAME"
    echo "${YELLOW}Остановка сервиса $SERVICE_NAME...${NC}"
    
    systemctl stop "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        log "Сервис $SERVICE_NAME успешно остановлен"
        echo "${GREEN}Сервис успешно остановлен!${NC}"
    else
        log "Ошибка при остановке сервиса $SERVICE_NAME"
        echo "${RED}Ошибка при остановке сервиса!${NC}"
    fi
    
    check_status
}

# Перезагрузка конфигурации systemd
reload_systemd() {
    log "Перезагрузка конфигурации systemd"
    echo "${YELLOW}Перезагрузка конфигурации systemd...${NC}"
    
    systemctl daemon-reload
    
    if [ $? -eq 0 ]; then
        log "Конфигурация systemd успешно перезагружена"
        echo "${GREEN}Конфигурация systemd успешно перезагружена!${NC}"
    else
        log "Ошибка при перезагрузке конфигурации systemd"
        echo "${RED}Ошибка при перезагрузке конфигурации systemd!${NC}"
    fi
}

# Проверка конфигурации сервиса
check_service_config() {
    log "Проверка конфигурации сервиса $SERVICE_NAME"
    echo "${YELLOW}Проверка конфигурации сервиса $SERVICE_NAME...${NC}"
    
    echo -e "\n${GREEN}=== Информация о сервисе ===${NC}"
    systemctl show "$SERVICE_NAME" | grep -E 'ExecStart|WorkingDirectory|User|Restart|Environment'
    
    echo -e "\n${GREEN}=== Содержимое файла сервиса ===${NC}"
    cat "/etc/systemd/system/$SERVICE_NAME.service"
    
    echo -e "\n${GREEN}=== Переменные окружения ===${NC}"
    if [ -f "$INSTALL_DIR/.env" ]; then
        cat "$INSTALL_DIR/.env"
    else
        echo "${YELLOW}Файл .env не найден${NC}"
    fi
    
    press_any_key
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    service_management_menu
fi