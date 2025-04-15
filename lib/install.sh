#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh
source ./lib/ssl.sh
source ./lib/antizapret.sh

# Проверка зависимостей
check_dependencies() {
    local missing=0
    declare -A deps=(
        ["python3"]="Python 3"
        ["pip"]="Python pip"
        ["git"]="Git"
        ["openssl"]="OpenSSL"
    )
    
    for cmd in "${!deps[@]}"; do
        if ! command -v "$cmd" >/dev/null; then
            echo "${RED}Ошибка: ${deps[$cmd]} не установлен${NC}"
            missing=$((missing+1))
        fi
    done
    
    [ $missing -eq 0 ] && return 0 || return 1
}

# Инициализация базы данных
init_db() {
    log "Инициализация базы данных"
    echo "${YELLOW}Инициализация базы данных...${NC}"
    PYTHONIOENCODING=utf-8 "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py"
    check_error "Не удалось инициализировать базу данных"
}

# Настройка фаервола
configure_firewall() {
    log "Настройка фаервола для порта $APP_PORT"
    if command -v ufw >/dev/null; then
        echo "${YELLOW}Настройка UFW...${NC}"
        ufw allow "$APP_PORT/tcp"
        
        if [ "$ssl_choice" = "1" ]; then
            ufw allow 80/tcp
            ufw allow 443/tcp
        fi
        
        ufw reload
    elif command -v firewall-cmd >/dev/null; then
        echo "${YELLOW}Настройка firewalld...${NC}"
        firewall-cmd --permanent --add-port="$APP_PORT/tcp"
        
        if [ "$ssl_choice" = "1" ]; then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
        fi
        
        firewall-cmd --reload
    else
        echo "${YELLOW}Фаервол не найден, пропускаем настройку${NC}"
    fi
}

# Валидация конфигурации
validate_config() {
    local errors=0
    
    echo "${YELLOW}Проверка конфигурации...${NC}"
    
    # Проверка файла .env
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo "${RED}Ошибка: .env файл не найден${NC}"
        errors=$((errors+1))
    fi
    
    # Проверка секретного ключа
    if ! grep -q "SECRET_KEY=" "$INSTALL_DIR/.env"; then
        echo "${RED}Ошибка: SECRET_KEY не установлен${NC}"
        errors=$((errors+1))
    fi
    
    # Проверка базы данных
    if [ ! -f "$DB_FILE" ]; then
        echo "${RED}Ошибка: База данных не найдена${NC}"
        errors=$((errors+1))
    fi
    
    # Проверка сервиса systemd
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

# Установка AdminAntizapret
install() {
    clear
    printf "%s\n" "${GREEN}"
    printf "┌────────────────────────────────────────────┐\n"
    printf "│          Установка AdminAntizapret         │\n"
    printf "└────────────────────────────────────────────┘\n"
    printf "%s\n" "${NC}"

    # Запрос параметров
    read -p "Введите порт для сервиса [$DEFAULT_PORT]: " APP_PORT
    APP_PORT=${APP_PORT:-$DEFAULT_PORT}
    
    # Проверка занятости порта
    while check_port $APP_PORT; do
        echo "${RED}Порт $APP_PORT уже занят!${NC}"
        read -p "Введите другой порт: " APP_PORT
    done

    # Выбор способа установки
    echo "${YELLOW}Выберите способ установки:${NC}"
    echo "1) Nginx + Let's Encrypt (рекомендуется)"
    echo "2) Самоподписанный сертификат"
    echo "3) Только HTTP (без HTTPS)"
    read -p "Ваш выбор [1-3]: " ssl_choice

    case $ssl_choice in
        1)
            while true; do
                read -p "Введите доменное имя (например, example.com): " DOMAIN
                if validate_domain "$DOMAIN"; then
                    break
                fi
            done
            
            while true; do
                read -p "Введите email для Let's Encrypt: " EMAIL
                if [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                    break
                else
                    echo "${RED}Неверный формат email!${NC}"
                fi
            done
            
            if ! check_dns; then
                echo "${YELLOW}Продолжение без корректной DNS записи может привести к ошибкам.${NC}"
                read -p "Продолжить установку? (y/n): " choice
                [[ "$choice" =~ ^[Yy]$ ]] || exit 1
            fi
            ;;
        2)
            setup_selfsigned
            ;;
        3)
            echo "${YELLOW}Будет использовано HTTP соединение без шифрования${NC}"
            ;;
        *)
            echo "${RED}Неверный выбор!${NC}"
            exit 1
            ;;
    esac

    # Обновление пакетов
    echo "${YELLOW}Обновление списка пакетов...${NC}"
    apt-get update -qq
    check_error "Не удалось обновить пакеты"
    
    # Проверка и установка зависимостей
    echo "${YELLOW}Установка системных зависимостей...${NC}"
    check_dependencies || {
        echo "${YELLOW}Попытка установить отсутствующие зависимости...${NC}"
        apt-get install -y -qq python3 python3-pip python3-venv git wget openssl >/dev/null 2>&1
        check_error "Не удалось установить зависимости"
    }

    # Создание виртуального окружения
    echo "${YELLOW}Создание виртуального окружения...${NC}"
    python3 -m venv "$VENV_PATH"
    check_error "Не удалось создать виртуальное окружение"

    # Установка Python-зависимостей
    echo "${YELLOW}Установка Python-зависимостей из requirements.txt...${NC}"
    "$VENV_PATH/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
    check_error "Не удалось установить Python-зависимости"
    
    # Настройка конфигурации
    echo "${YELLOW}Настройка конфигурации...${NC}"

    # Проверка наличия файла .env
    if [ -f "$INSTALL_DIR/.env" ]; then
        echo "${YELLOW} Добавляем значения в файл .env...${NC}"
        
        # Проверяем, есть ли уже строки SECRET_KEY и APP_PORT
        grep -qxF "SECRET_KEY='$SECRET_KEY'" "$INSTALL_DIR/.env" || echo "SECRET_KEY='$SECRET_KEY'" >> "$INSTALL_DIR/.env"
        grep -qxF "APP_PORT=$APP_PORT" "$INSTALL_DIR/.env" || echo "APP_PORT=$APP_PORT" >> "$INSTALL_DIR/.env"
    else
        # Если файл не существует, создаем его с необходимыми значениями
        echo "${YELLOW} Файл .env не найден, создаем новый...${NC}"
        cat > "$INSTALL_DIR/.env" <<EOL
SECRET_KEY='$SECRET_KEY'
APP_PORT=$APP_PORT
EOL
        chmod 600 "$INSTALL_DIR/.env"
    fi

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

    # Настройка выбранного способа HTTPS
    case $ssl_choice in
        1)
            setup_nginx_letsencrypt
            ;;
        2)
            systemctl restart "$SERVICE_NAME"
            ;;
        3)
            echo "${YELLOW}HTTP режим активирован${NC}"
            ;;
    esac

    # Настройка фаервола
    configure_firewall

    # Проверка установки AntiZapret-VPN
    echo "${YELLOW}Проверка установки AntiZapret-VPN...${NC}"
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "${GREEN}"
        echo "┌────────────────────────────────────────────┐"
        echo "│   Установка успешно завершена!             │"
        echo "├────────────────────────────────────────────┤"
        case $ssl_choice in
            1)
                echo "│ Адрес: https://$DOMAIN"
                ;;
            2)
                echo "│ Адрес: https://$(hostname -I | awk '{print $1}'):$APP_PORT"
                ;;
            3)
                echo "│ Адрес: http://$(hostname -I | awk '{print $1}'):$APP_PORT"
                ;;
        esac
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

    # Установка прав выполнения для client.sh и doall.sh
    echo "${YELLOW}Установка прав выполнения для client.sh и doall.sh...${NC}"
    chmod +x "$INSTALL_DIR/client.sh" "$ANTIZAPRET_INSTALL_DIR/doall.sh"
    if [ $? -eq 0 ]; then
        echo "${GREEN}Права выполнения успешно установлены!${NC}"
    else
        echo "${RED}Ошибка при установке прав выполнения!${NC}"
    fi

    # Проверка и установка AntiZapret-VPN
    if ! check_antizapret_installed; then
        echo "${YELLOW}AntiZapret-VPN не установлен. Установить сейчас? (y/n)${NC}"
        read -r answer
        case $answer in
            [Yy]*) install_antizapret;;
            *) echo "${YELLOW}Пропускаем установку AntiZapret-VPN${NC}";;
        esac
    else
        echo "${GREEN}AntiZapret-VPN уже установлен.${NC}"
    fi

    # Валидация конфигурации
    validate_config

    press_any_key
}

# Удаление сервиса
uninstall() {
    printf "%s\n" "${YELLOW}Подготовка к удалению AdminAntizapret...${NC}"
    printf "%s\n" "${RED}ВНИМАНИЕ! Это действие необратимо!${NC}"
    
    printf "Вы уверены, что хотите удалить AdminAntizapret? (y/n) "
    read answer
    
    case "$answer" in
        [Yy]*)
            # Создать резервную копию перед удалением
            create_backup
            
            # Определяем способ установки для правильного удаления
            use_nginx=false
            use_letsencrypt=false
            use_selfsigned=false
            
            # Проверяем, используется ли Nginx
            if [ -f "/etc/nginx/sites-enabled/admin-antizapret" ]; then
                use_nginx=true
                # Проверяем, используется ли Let's Encrypt
                if [ -d "/etc/letsencrypt/live/" ]; then
                    use_letsencrypt=true
                fi
            fi
            
            # Проверяем, используется ли самоподписанный сертификат
            if grep -q "USE_HTTPS=true" "$INSTALL_DIR/.env" 2>/dev/null && \
               [ -f "/etc/ssl/certs/admin-antizapret.crt" ] && \
               [ -f "/etc/ssl/private/admin-antizapret.key" ]; then
                use_selfsigned=true
            fi
            
            # Остановка и удаление сервиса
            printf "%s\n" "${YELLOW}Остановка сервиса...${NC}"
            systemctl stop $SERVICE_NAME
            systemctl disable $SERVICE_NAME
            rm -f "/etc/systemd/system/$SERVICE_NAME.service"
            systemctl daemon-reload
            
            # Удаление конфигурации Nginx, если использовался
            if [ "$use_nginx" = true ]; then
                printf "%s\n" "${YELLOW}Удаление конфигурации Nginx...${NC}"
                rm -f /etc/nginx/sites-enabled/admin-antizapret
                rm -f /etc/nginx/sites-available/admin-antizapret
                systemctl reload nginx
                
                # Удаление Let's Encrypt сертификата, если использовался
                if [ "$use_letsencrypt" = true ]; then
                    printf "%s\n" "${YELLOW}Удаление Let's Encrypt сертификата...${NC}"
                    certbot delete --non-interactive --cert-name $DOMAIN 2>/dev/null || \
                        echo "${YELLOW}Не удалось удалить сертификат Let's Encrypt, возможно он уже удален${NC}"
                    
                    # Удаление задания cron для обновления сертификатов
                    crontab -l | grep -v 'certbot renew' | crontab -
                fi
            fi
            
            # Удаление самоподписанного сертификата, если использовался
            if [ "$use_selfsigned" = true ]; then
                printf "%s\n" "${YELLOW}Удаление самоподписанного сертификата...${NC}"
                rm -f /etc/ssl/certs/admin-antizapret.crt
                rm -f /etc/ssl/private/admin-antizapret.key
            fi
            
            # Удаление файлов приложения
            printf "%s\n" "${YELLOW}Удаление файлов...${NC}"
            rm -rf "$INSTALL_DIR"
            rm -f /root/adminpanel/adminpanel.sh
            
            # Удаление зависимостей, если они больше не нужны
            printf "%s\n" "${YELLOW}Очистка зависимостей...${NC}"
            apt-get autoremove -y --purge python3-venv python3-pip nginx nginx-common >/dev/null 2>&1
        
            # Удаление файлов приложения
            printf "%s\n" "${YELLOW}Удаление логов...${NC}"
            rm -f "$LOG_FILE"

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

# Автоматическое обновление
auto_update() {
    log "Проверка обновлений"
    echo "${YELLOW}Проверка обновлений...${NC}"
    cd "$INSTALL_DIR" || return 1
    
    # Fetch updates
    git fetch origin main
    
    # Check if update needed
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