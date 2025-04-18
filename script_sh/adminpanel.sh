#!/bin/bash

# Полный менеджер AdminAntizapret

export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"

# Цвета для вывода
RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
NC=$(printf '\033[0m') # No Color

# Основные параметры
INSTALL_DIR="/opt/AdminAntizapret"
VENV_PATH="$INSTALL_DIR/venv"
SERVICE_NAME="admin-antizapret"
DEFAULT_PORT="5050"
APP_PORT="$DEFAULT_PORT"
DB_FILE="$INSTALL_DIR/instance/users.db"
ANTIZAPRET_INSTALL_DIR="/root/antizapret"
ANTIZAPRET_INSTALL_SCRIPT="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup.sh"
LOG_FILE="/var/log/adminpanel.log"
INCLUDE_DIR="$INSTALL_DIR/script_sh"

if [ -f "$INCLUDE_DIR/ssl_setup.sh" ]; then
    . "$INCLUDE_DIR/ssl_setup.sh"
else
    echo "${RED}Ошибка: не найден файл ssl_setup.sh${NC}"
    exit 1
fi

# Генерируем случайный секретный ключ
SECRET_KEY=$(openssl rand -hex 32)

# Инициализация логгирования
init_logging() {
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Запуск скрипта"
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Функция проверки занятости порта
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

# Проверка зависимостей
check_dependencies() {
    echo "${YELLOW}Установка зависимостей...${NC}" 
    apt-get update --quiet --quiet && apt-get install -y --quiet --quiet python3 python3-pip git wget openssl python3-venv > /dev/null 
    check_error "Не удалось установить зависимости"
    echo "${GREEN}Зависимости установлены.${NC}"
}

# Функция проверки ошибок
check_error() {
  if [ $? -ne 0 ]; then
    log "Ошибка при выполнении: $1"
    printf "%s\n" "${RED}Ошибка при выполнении: $1${NC}" >&2
    exit 1
  fi
}

# Проверка прав root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Попытка запуска без прав root"
    printf "%s\n" "${RED}Этот скрипт должен быть запущен с правами root!${NC}" >&2
    exit 1
  fi
}

# Ожидание нажатия клавиши
press_any_key() {
  printf "\n%s\n" "${YELLOW}Нажмите любую клавишу чтобы продолжить...${NC}"
  read -r _
}

# Проверка установки AntiZapret-VPN
check_antizapret_installed() {
  [ -d "$ANTIZAPRET_INSTALL_DIR" ]
}

# Установка AntiZapret-VPN
install_antizapret() {
    log "Проверка наличия AntiZapret-VPN"
    echo "${YELLOW}Проверка установленного AntiZapret-VPN...${NC}"

    # Функция проверки установки AntiZapret
    check_antizapret_installed() {
        if systemctl is-active --quiet antizapret.service 2>/dev/null; then
            return 0
        fi
        if [ -d "/root/antizapret" ]; then
            return 0
        fi
        return 1
    }

    # Проверяем установлен ли AntiZapret
    if check_antizapret_installed; then
        log "AntiZapret-VPN обнаружен в системе"
        echo "${GREEN}AntiZapret-VPN уже установлен (обнаружен сервис или директория).${NC}"
        return 0
    fi

    log "AntiZapret-VPN не установлен"
    echo "${RED}ВНИМАНИЕ! Модуль AntiZapret-VPN не установлен!${NC}"
    echo ""
    echo "${YELLOW}Это обязательный компонент для работы системы.${NC}"
    echo "Пожалуйста, установите его вручную следующими командами:"
    echo ""
    echo "1. Скачайте и запустите установочный скрипт:"
    echo "${CYAN} bash <(wget --no-hsts -qO- https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup.sh) | bash${NC}"
    echo ""
    echo "2. Затем запустите этот скрипт снова"
    echo ""
    echo "${YELLOW}Без этого модуля работа системы невозможна.${NC}"
    echo ""
    exit 1
}

# Инициализация базы данных
init_db() {
  log "Инициализация базы данных"
  echo "${YELLOW}Инициализация базы данных...${NC}"
  PYTHONIOENCODING=utf-8 "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py"
  check_error "Не удалось инициализировать базу данных"
}

# Валидация конфигурации
validate_config() {
    local errors=0
    
    echo "${YELLOW}Проверка конфигурации...${NC}"
    
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo "${RED}Ошибка: .env файл не найден${NC}"
        errors=$((errors+1))
    fi
    
    if ! grep -q "SECRET_KEY=" "$INSTALL_DIR/.env"; then
        echo "${RED}Ошибка: SECRET_KEY не установлен${NC}"
        errors=$((errors+1))
    fi
    
    if [ ! -f "$DB_FILE" ]; then
        echo "${RED}Ошибка: База данных не найдена${NC}"
        errors=$((errors+1))
    fi
    
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo "${RED}Ошибка: Сервис systemd не найден${NC}"
        errors=$((errors+1))
    fi
    
    if [ $errors -eq 0 ]; then
        echo "${GREEN}Конфигурация в порядке.${NC}"
        return 0
    else
        echo "${RED}Найдено $errors ошибок в конфигурации.${NC}"
        return 1
    fi
}

# Создание резервной копии
create_backup() {
    local backup_dir="/var/backups/antizapret"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/full_backup_$timestamp.tar.gz"
    
    log "Создание резервной копии в $backup_file"
    echo "${YELLOW}Создание полной резервной копии...${NC}"
    mkdir -p "$backup_dir"
    
    tar -czf "$backup_file" \
        "$INSTALL_DIR" \
        /etc/systemd/system/$SERVICE_NAME.service \
        "$DB_FILE" \
        /etc/ssl/certs/admin-antizapret.crt 2>/dev/null \
        /etc/ssl/private/admin-antizapret.key 2>/dev/null \
        /etc/letsencrypt/live/$DOMAIN 2>/dev/null
    
    if ! tar -tzf "$backup_file" >/dev/null; then
        echo "${RED}Ошибка: резервная копия повреждена!${NC}"
        rm -f "$backup_file"
        return 1
    fi
    
    echo "${GREEN}Резервная копия создана:${NC}"
    ls -lh "$backup_file"
    echo "Для восстановления используйте: $0 --restore $backup_file"
    press_any_key
}

# Восстановление из резервной копии
restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        echo "${RED}Файл резервной копии не найден!${NC}"
        return 1
    fi
    
    log "Восстановление из резервной копии $backup_file"
    echo "${YELLOW}Восстановление из резервной копии...${NC}"
    
    systemctl stop $SERVICE_NAME 2>/dev/null
    tar -xzf "$backup_file" -C /
    systemctl daemon-reload
    systemctl start $SERVICE_NAME
    
    log "Восстановление завершено"
    echo "${GREEN}Восстановление завершено успешно!${NC}"
}

# Автоматическое обновление
auto_update() {
    log "Проверка обновлений"
    echo "${YELLOW}Проверка обновлений...${NC}"
    cd "$INSTALL_DIR" || return 1
    
    git fetch origin main
    
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "${GREEN}Найдены обновления. Установка...${NC}"
        git pull origin main
        "$VENV_PATH/bin/pip" install -q -r requirements.txt
        systemctl restart $SERVICE_NAME
        echo "${GREEN}Обновление завершено!${NC}"
    else
        echo "${GREEN}Система актуальна.${NC}"
    fi
}

# Мониторинг системы
show_monitor() {
    while true; do
        clear
        echo "${GREEN}┌────────────────────────────────────────────┐"
        echo "│          Мониторинг системы              │"
        echo "├────────────────────────────────────────────┤"
        echo "│ 1. Проверить использование CPU            │"
        echo "│ 2. Проверить использование памяти        │"
        echo "│ 3. Проверить использование диска         │"
        echo "│ 4. Просмотреть логи сервиса              │"
        echo "│ 5. Проверить сетевые соединения          │"
        echo "│ 0. Назад                                 │"
        echo "└────────────────────────────────────────────┘${NC}"
        
        read -p "Выберите действие: " choice
        case $choice in
            1) top -bn1 | grep "Cpu(s)" ;;
            2) free -h ;;
            3) df -h ;;
            4) journalctl -u $SERVICE_NAME -n 50 --no-pager ;;
            5) netstat -tuln ;;
            0) break ;;
            *) echo "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
        press_any_key
    done
}

# Удаление сервиса
uninstall() {
    printf "%s\n" "${YELLOW}Подготовка к удалению AdminAntizapret...${NC}"
    printf "%s\n" "${RED}ВНИМАНИЕ! Это действие необратимо!${NC}"
    
    printf "Вы уверены, что хотите удалить AdminAntizapret? (y/n) "
    read answer
    
    answer=$(echo "$answer" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    case "$answer" in
        [Yy]*)
            create_backup
            
            use_selfsigned=false
            use_letsencrypt=false
            
            if grep -q "USE_HTTPS=true" "$INSTALL_DIR/.env" 2>/dev/null; then
                if [ -f "/etc/ssl/certs/admin-antizapret.crt" ] && \
                   [ -f "/etc/ssl/private/admin-antizapret.key" ]; then
                    use_selfsigned=true
                elif [ -d "/etc/letsencrypt/live/" ]; then
                    use_letsencrypt=true
                fi
            fi
            
            printf "%s\n" "${YELLOW}Остановка сервиса...${NC}"
            systemctl stop $SERVICE_NAME
            systemctl disable $SERVICE_NAME
            rm -f "/etc/systemd/system/$SERVICE_NAME.service"
            systemctl daemon-reload
            
            if [ "$use_selfsigned" = true ]; then
                printf "%s\n" "${YELLOW}Удаление самоподписанного сертификата...${NC}"
                rm -f /etc/ssl/certs/admin-antizapret.crt
                rm -f /etc/ssl/private/admin-antizapret.key
            fi
            
            if [ "$use_letsencrypt" = true ]; then
                printf "%s\n" "${YELLOW}Удаление Let's Encrypt сертификата...${NC}"
                certbot delete --non-interactive --cert-name $DOMAIN 2>/dev/null || \
                    echo "${YELLOW}Не удалось удалить сертификат Let's Encrypt${NC}"
                crontab -l | grep -v 'certbot renew' | crontab -
            fi
            
            printf "%s\n" "${YELLOW}Удаление файлов...${NC}"
            rm -rf "$INSTALL_DIR"
            rm -f "$LOG_FILE"
            
            printf "%s\n" "${YELLOW}Очистка зависимостей...${NC}"
            apt-get autoremove -y --purge python3-venv python3-pip certbot >/dev/null 2>&1
        
            printf "%s\n" "${GREEN}Удаление завершено успешно!${NC}"
            printf "Резервная копия сохранена в /var/backups/antizapret\n"
            press_any_key
            exit 0
            ;;
        *)
            printf "%s\n" "${GREEN}Удаление отменено.${NC}"
            press_any_key
            return
            ;;
    esac
}

# Добавление администратора
add_admin() {
    echo "${YELLOW}Добавление нового администратора...${NC}"

    while true; do
        read -p "Введите логин администратора: " username
        username=$(echo "$username" | tr -d '[:space:]')  
        
        if [ -z "$username" ]; then
            echo "${RED}Логин не может быть пустым!${NC}"
        elif [[ "$username" =~ [^a-zA-Z0-9_-] ]]; then
            echo "${RED}Логин может содержать только буквы, цифры, '-' и '_'!${NC}"
        else
            break
        fi
    done
    
    # Запрос пароля с проверкой
    while true; do
        read -s -p "Введите пароль: " password
        echo
        read -s -p "Повторите пароль: " password_confirm
        echo
        
        password=$(echo "$password" | xargs)
        password_confirm=$(echo "$password_confirm" | xargs)
        
        if [ -z "$password" ]; then
            echo "${RED}Пароль не может быть пустым!${NC}"
        elif [ "$password" != "$password_confirm" ]; then
            echo "${RED}Пароли не совпадают! Попробуйте снова.${NC}"
        elif [ ${#password} -lt 8 ]; then
            echo "${RED}Пароль должен содержать минимум 8 символов!${NC}"
        else
            break
        fi
    done

    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --add-user "$username" "$password"
    check_error "Не удалось добавить администратора"
    press_any_key
}

# Удаление администратора
delete_admin() {
    echo "${YELLOW}Удаление администратора...${NC}"
    
    echo "${YELLOW}Список администраторов:${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --list-users
    if [ $? -ne 0 ]; then
        echo "${RED}Ошибка при получении списка администраторов!${NC}"
        press_any_key
        return
    fi

    read -p "Введите логин администратора для удаления: " username
    if [ -z "$username" ]; then
        echo "${RED}Логин не может быть пустым!${NC}"
        press_any_key
        return
    fi

    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --delete-user "$username"
    if [ $? -eq 0 ]; then
        echo "${GREEN}Администратор '$username' успешно удалён!${NC}"
    else
        echo "${RED}Ошибка при удалении администратора '$username'!${NC}"
    fi
    press_any_key
}

# Перезапуск сервиса
restart_service() {
    echo "${YELLOW}Перезапуск сервиса...${NC}"
    systemctl restart $SERVICE_NAME
    check_status
}

# Проверка статуса
check_status() {
    echo "${YELLOW}Статус сервиса:${NC}"
    systemctl status $SERVICE_NAME --no-pager -l
    press_any_key
}

# Просмотр логов
show_logs() {
    echo "${YELLOW}Log File:${NC}"
    journalctl -u $SERVICE_NAME -n 50 --no-pager
    press_any_key
}

# Проверка обновлений
check_updates() {
    auto_update
    press_any_key
}

# Проверка и установка прав выполнения для файлов
check_and_set_permissions() {
  echo "${YELLOW}Проверка и установка прав выполнения для client.sh и doall.sh...${NC}"
  
  files=("$INSTALL_DIR/client.sh" "$ANTIZAPRET_INSTALL_DIR/doall.sh")
  for file in "${files[@]}"; do
    if [ -f "$file" ]; then
      if [ ! -x "$file" ]; then
        chmod +x "$file"
        if [ $? -eq 0 ]; then
          echo "${GREEN}Права выполнения установлены для $file${NC}"
        else
          echo "${RED}Ошибка при установке прав выполнения для $file!${NC}"
        fi
      else
        echo "${GREEN}Права выполнения уже установлены для $file${NC}"
      fi
    else
      echo "${RED}Файл $file не найден!${NC}"
    fi
  done
  
  press_any_key
}

change_port() {
    echo "${YELLOW}Изменение порта сервиса...${NC}"
    read -p "Введите новый порт: " new_port
    
    # Проверка валидности порта
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo "${RED}Неверный номер порта! Должен быть от 1 до 65535.${NC}"
        press_any_key
        return
    fi

    # Проверка занятости порта (опционально)
    if lsof -i :"$new_port" > /dev/null 2>&1; then
        echo "${RED}Порт $new_port уже занят!${NC}"
        press_any_key
        return
    fi

    # Обновляем .env (заменяем существующее значение)
    if [ -f "$INSTALL_DIR/.env" ]; then
        sed -i "/^APP_PORT=/d" "$INSTALL_DIR/.env"
    fi
    echo "APP_PORT=$new_port" >> "$INSTALL_DIR/.env"

    echo "${GREEN}Порт изменен на $new_port. Перезапустите сервис для применения изменений.${NC}"
    press_any_key
}

# Главное меню
main_menu() {
    while true; do
        clear
        printf "%s\n" "${GREEN}"
        printf "┌────────────────────────────────────────────┐\n"
        printf "│          Меню управления AdminAntizapret   │\n"
        printf "├────────────────────────────────────────────┤\n"
        printf "│ 1. Добавить администратора                 │\n"
        printf "│ 2. Удалить администратора                  │\n"
        printf "│ 3. Перезапустить сервис                    │\n"
        printf "│ 4. Проверить статус сервиса                │\n"
        printf "│ 5. Просмотреть логи                        │\n"
        printf "│ 6. Проверить обновления                    │\n"
        printf "│ 7. Создать резервную копию                 │\n"
        printf "│ 8. Восстановить из резервной копии         │\n"
        printf "│ 9. Удалить AdminAntizapret                 │\n"
        printf "│ 10. Проверить и установить права           │\n"
        printf "│ 11. Изменить порт сервиса                  │\n"
        printf "│ 12. Мониторинг системы                     │\n"
        printf "│ 13. Проверить конфигурацию                 │\n"
        printf "│ 0. Выход                                   │\n"
        printf "└────────────────────────────────────────────┘\n"
        printf "%s\n" "${NC}"
        
        read -p "Выберите действие [0-13]: " choice
        case $choice in
            1) add_admin ;;
            2) delete_admin ;;
            3) restart_service ;;
            4) check_status ;;
            5) show_logs ;;
            6) check_updates ;;
            7) create_backup ;;
            8) 
                read -p "Введите путь к файлу резервной копии: " backup_file
                restore_backup "$backup_file"
                press_any_key
                ;;
            9) uninstall ;;
            10) check_and_set_permissions ;;
            11) change_port ;;
            12) show_monitor ;;
            13) validate_config; press_any_key ;;
            0) exit 0 ;;
            *) printf "%s\n" "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Установка AdminAntizapret
install() {
    clear
    printf "%s\n" "${GREEN}"
    printf "┌────────────────────────────────────────────┐\n"
    printf "│          Установка AdminAntizapret         │\n"
    printf "└────────────────────────────────────────────┘\n"
    printf "%s\n" "${NC}"

    # Проверка установки AntiZapret-VPN
    echo "${YELLOW}Проверка установки AntiZapret-VPN...${NC}"
    if ! check_antizapret_installed; then
        install_antizapret
    fi
    
    # Установка прав выполнения
    echo "${YELLOW}Установка прав выполнения...${NC}"
    chmod +x "$INSTALL_DIR/client.sh" "$ANTIZAPRET_INSTALL_DIR/doall.sh" 2>/dev/null || true

    # Обновление пакетов
    echo "${YELLOW}Обновление списка пакетов...${NC}"
    apt-get update --quiet --quiet > /dev/null
    check_error "Не удалось обновить пакеты"
    
    # Проверка и установка зависимостей
    check_dependencies

    # Создание виртуального окружения
    echo "${YELLOW}Создание виртуального окружения...${NC}"
    python3 -m venv "$VENV_PATH"
    check_error "Не удалось создать виртуальное окружение"

    # Установка Python-зависимостей
    echo "${YELLOW}Установка Python-зависимостей...${NC}"
    "$VENV_PATH/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
    check_error "Не удалось установить Python-зависимости"

    # Выбор способа установки
    choose_installation_type || exit 1

    # Инициализация базы данных
    init_db

    # Создание systemd сервиса
    echo "${YELLOW}Создание systemd сервиса...${NC}"
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOL
[Unit]
Description=AdminAntizapret VPN Management
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$VENV_PATH/bin/python $INSTALL_DIR/app.py
Restart=always
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOL

    # Включение и запуск сервиса
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    check_error "Не удалось запустить сервис"

    # Проверка установки
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "${GREEN}"
        echo "┌────────────────────────────────────────────┐"
        echo "│   Установка успешно завершена!             │"
        echo "├────────────────────────────────────────────┤"
        
        if grep -q "USE_HTTPS=true" "$INSTALL_DIR/.env"; then
            if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                echo "│ Адрес: https://$DOMAIN:$APP_PORT"
            elif [ -f "$INSTALL_DIR/.env" ] && grep -q "DOMAIN=" "$INSTALL_DIR/.env"; then
                DOMAIN=$(grep "DOMAIN=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
                echo "│ Адрес: https://$DOMAIN:$APP_PORT"
            else
                echo "│ Адрес: https://$(hostname -I | awk '{print $1}'):$APP_PORT"
            fi
        else
            echo "│ Адрес: http://$(hostname -I | awk '{print $1}'):$APP_PORT"
        fi
        
        echo "│"
        echo "│ Для входа используйте учетные данные,"
        echo "│ созданные при инициализации базы данных"
        echo "└────────────────────────────────────────────┘"
        echo "${NC}"
    else
        echo "${RED}Ошибка при запуске сервиса!${NC}"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
        exit 1
    fi

    press_any_key
}

# Главная функция
main() {
    check_root
    init_logging
    
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
        *)
            if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
                printf "%s\n" "${YELLOW}AdminAntizapret не установлен.${NC}"
                printf "Хотите установить? (y/n) "
                read -r answer
                    answer=$(echo "$answer" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                case $answer in
                    [Yy]*) install; main_menu ;;
                    *) exit 0 ;;
                esac
            else
                main_menu
            fi
            ;;
    esac
}

# Запуск скрипта
main "$@"