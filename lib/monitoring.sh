#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Основная функция мониторинга
show_monitor() {
    while true; do
        clear
        echo "${GREEN}┌────────────────────────────────────────────┐"
        echo "│          Системный мониторинг            │"
        echo "├────────────────────────────────────────────┤"
        echo "│ 1. Общая информация о системе            │"
        echo "│ 2. Использование CPU                     │"
        echo "│ 3. Использование памяти                  │"
        echo "│ 4. Использование диска                   │"
        echo "│ 5. Сетевые соединения                    │"
        echo "│ 6. Логи сервиса                          │"
        echo "│ 7. Проверить обновления                  │"
        echo "│ 8. Мониторинг в реальном времени         │"
        echo "│ 0. Назад                                 │"
        echo "└────────────────────────────────────────────┘${NC}"
        
        read -p "Выберите действие: " choice
        case $choice in
            1) show_system_info ;;
            2) show_cpu_usage ;;
            3) show_memory_usage ;;
            4) show_disk_usage ;;
            5) show_network_info ;;
            6) show_service_logs ;;
            7) check_updates ;;
            8) realtime_monitoring ;;
            0) break ;;
            *) echo "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Общая информация о системе
show_system_info() {
    clear
    echo "${GREEN}=== Общая информация о системе ===${NC}"
    
    # Информация о системе
    echo -e "\n${YELLOW}Система:${NC}"
    echo "ОС: $(lsb_release -d | cut -f2-)"
    echo "Ядро: $(uname -r)"
    echo "Время работы: $(uptime -p | sed 's/up //')"
    echo "Дата/время: $(date)"
    
    # Информация о процессоре
    echo -e "\n${YELLOW}Процессор:${NC}"
    echo "Модель: $(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^[ \t]*//')"
    echo "Ядер: $(grep -c "^processor" /proc/cpuinfo)"
    
    # Информация о сервисе
    echo -e "\n${YELLOW}Сервис $SERVICE_NAME:${NC}"
    systemctl status $SERVICE_NAME --no-pager -l | grep -E "Active:|Loaded:|Main PID:"
    
    press_any_key
}

# Использование CPU
show_cpu_usage() {
    clear
    echo "${GREEN}=== Использование CPU ===${NC}"
    
    # Общая информация
    echo -e "\n${YELLOW}Загрузка CPU:${NC}"
    top -bn1 | grep "Cpu(s)" | sed 's/,/ /g' | awk '{printf "Пользователь: %.1f%%\nСистема: %.1f%%\nОжидание: %.1f%%\n", $2, $4, $8}'
    
    # Подробная статистика
    echo -e "\n${YELLOW}Статистика по процессам:${NC}"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 10
    
    press_any_key
}

# Использование памяти
show_memory_usage() {
    clear
    echo "${GREEN}=== Использование памяти ===${NC}"
    
    # Общая информация
    echo -e "\n${YELLOW}Использование памяти:${NC}"
    free -h
    
    # Подробная статистика
    echo -e "\n${YELLOW}Топ процессов по памяти:${NC}"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -n 10
    
    press_any_key
}

# Использование диска
show_disk_usage() {
    clear
    echo "${GREEN}=== Использование диска ===${NC}"
    
    # Общая информация
    echo -e "\n${YELLOW}Смонтированные разделы:${NC}"
    df -h | grep -v "tmpfs"
    
    # Подробная информация
    echo -e "\n${YELLOW}Крупнейшие директории:${NC}"
    du -sh /* 2>/dev/null | sort -hr | head -n 10
    
    press_any_key
}

# Сетевые соединения
show_network_info() {
    clear
    echo "${GREEN}=== Сетевые соединения ===${NC}"
    
    # Интерфейсы
    echo -e "\n${YELLOW}Сетевые интерфейсы:${NC}"
    ip -br a | grep -v "lo"
    
    # Активные соединения
    echo -e "\n${YELLOW}Активные соединения:${NC}"
    ss -tulnp | grep -v "127.0.0.1"
    
    # Статистика
    echo -e "\n${YELLOW}Статистика:${NC}"
    netstat -s | head -n 20
    
    press_any_key
}

# Логи сервиса
show_service_logs() {
    clear
    echo "${GREEN}=== Логи сервиса $SERVICE_NAME ===${NC}"
    
    # Последние 50 строк лога
    journalctl -u $SERVICE_NAME -n 50 --no-pager
    
    press_any_key
}

# Проверка обновлений
check_updates() {
    clear
    echo "${GREEN}=== Проверка обновлений ===${NC}"
    
    # Обновления системы
    echo -e "\n${YELLOW}Доступные обновления системы:${NC}"
    apt list --upgradable 2>/dev/null
    
    # Обновления Python пакетов
    echo -e "\n${YELLOW}Обновления Python пакетов:${NC}"
    $VENV_PATH/bin/pip list --outdated
    
    press_any_key
}

# Мониторинг в реальном времени
realtime_monitoring() {
    clear
    echo "${GREEN}=== Мониторинг в реальном времени ===${NC}"
    echo "${YELLOW}Для выхода нажмите Ctrl+C${NC}"
    
    # Запускаем htop или top, если htop не установлен
    if command -v htop >/dev/null; then
        htop
    else
        top
    fi
}