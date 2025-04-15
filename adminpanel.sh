#!/bin/bash

# Импорт всех необходимых модулей
source ./lib/config.sh
source ./lib/utils.sh
source ./lib/install.sh
source ./lib/ssl.sh
source ./lib/admin_management.sh
source ./lib/backup.sh
source ./lib/service.sh
source ./lib/monitoring.sh
source ./lib/maintenance.sh
source ./lib/antizapret.sh

# Инициализация логирования
init_logging() {
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Запуск скрипта adminpanel.sh"
}

# Главное меню
main_menu() {
    while true; do
        clear
        printf "%s\n" "${GREEN}"
        printf "┌────────────────────────────────────────────┐\n"
        printf "│      Панель управления AdminAntizapret      │\n"
        printf "├────────────────────────────────────────────┤\n"
        printf "│ 1. Управление администраторами             │\n"
        printf "│ 2. Управление сервисом                     │\n"
        printf "│ 3. Резервное копирование                   │\n"
        printf "│ 4. Мониторинг системы                      │\n"
        printf "│ 5. Режим обслуживания                      │\n"
        printf "│ 6. Управление AntiZapret-VPN               │\n"
        printf "│ 7. Настройки SSL/Nginx                     │\n"
        printf "│ 8. Проверить обновления                    │\n"
        printf "│ 0. Выход                                   │\n"
        printf "└────────────────────────────────────────────┘\n"
        printf "%s\n" "${NC}"
        
        printf "Выберите раздел [0-8]: "
        read choice
        case $choice in
            1) admin_management_menu ;;  # Меню из admin_management.sh
            2) service_management_menu ;; # Меню из service.sh
            3) backup_menu ;;           # Меню из backup.sh
            4) show_monitor ;;          # Функция из monitoring.sh
            5) maintenance_menu ;;      # Меню из maintenance.sh
            6) antizapret_menu ;;      # Меню из antizapret.sh
            7) ssl_management_menu ;;   # Меню из ssl.sh
            8) check_updates ;;         # Функция из install.sh
            0) exit 0 ;;
            *) printf "%s\n" "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Обработка аргументов командной строки
process_arguments() {
    case "$1" in
        "--install")
            install
            ;;
        "--update")
            auto_update
            ;;
        "--backup")
            create_backup
            ;;
        "--restore")
            if [ -z "$2" ]; then
                echo "${RED}Укажите файл для восстановления!${NC}"
                exit 1
            fi
            restore_backup "$2"
            ;;
        "--add-admin")
            add_admin
            ;;
        "--enable-maintenance")
            enable_maintenance
            ;;
        "--disable-maintenance")
            disable_maintenance
            ;;
        *)
            # Если аргументов нет, запускаем интерактивное меню
            if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
                printf "%s\n" "${YELLOW}AdminAntizapret не установлен.${NC}"
                printf "Хотите установить? (y/n) "
                read -r answer
                case $answer in
                    [Yy]*) 
                        install
                        main_menu
                        ;;
                    *) 
                        exit 0
                        ;;
                esac
            else
                main_menu
            fi
            ;;
    esac
}

# Главная функция
main() {
    check_root          # Проверка прав root из utils.sh
    init_logging       # Инициализация логирования
    
    # Обработка аргументов командной строки
    process_arguments "$@"
}

# Точка входа
main "$@"