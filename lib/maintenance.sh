#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Файл страницы обслуживания
MAINTENANCE_HTML="/var/www/html/maintenance.html"
# Временный файл конфигурации Nginx
NGINX_TEMP_CONF="/tmp/nginx_maintenance.conf"

# Включение режима обслуживания
enable_maintenance() {
    log "Активация режима обслуживания"
    echo "${YELLOW}Активация режима обслуживания...${NC}"

    # Проверяем, не активирован ли уже режим
    if [ -f "$MAINTENANCE_HTML" ]; then
        echo "${YELLOW}Режим обслуживания уже активирован.${NC}"
        return 0
    fi

    # Остановка сервиса
    echo "${YELLOW}Остановка сервиса $SERVICE_NAME...${NC}"
    systemctl stop $SERVICE_NAME
    check_error "Не удалось остановить сервис $SERVICE_NAME"

    # Создание страницы обслуживания
    echo "${YELLOW}Создание страницы обслуживания...${NC}"
    cat > "$MAINTENANCE_HTML" <<EOL
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>На сайте ведутся технические работы</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            padding: 50px; 
            color: #333;
        }
        h1 { color: #d9534f; }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
        }
        .logo { 
            max-width: 200px; 
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>На сайте ведутся технические работы</h1>
        <p>Приносим извинения за временные неудобства. Мы работаем над улучшением сервиса.</p>
        <p>Попробуйте зайти позже.</p>
        <p>Время начала работ: $(date "+%d.%m.%Y %H:%M:%S")</p>
    </div>
</body>
</html>
EOL

    # Настройка Nginx для режима обслуживания (если используется Nginx)
    if [ -f "/etc/nginx/sites-enabled/admin-antizapret" ]; then
        echo "${YELLOW}Настройка Nginx для режима обслуживания...${NC}"
        
        # Создаем временную конфигурацию
        cat > "$NGINX_TEMP_CONF" <<EOL
server {
    listen 80;
    server_name _;
    
    location / {
        root /var/www/html;
        try_files \$uri /maintenance.html =503;
    }
}

server {
    listen 443 ssl;
    server_name _;
    
    ssl_certificate /etc/ssl/certs/admin-antizapret.crt;
    ssl_certificate_key /etc/ssl/private/admin-antizapret.key;
    
    location / {
        root /var/www/html;
        try_files \$uri /maintenance.html =503;
    }
}
EOL

        # Заменяем текущую конфигурацию
        mv "$NGINX_TEMP_CONF" /etc/nginx/sites-enabled/admin-antizapret
        nginx -t && systemctl reload nginx
        check_error "Не удалось перезагрузить Nginx"
    fi

    log "Режим обслуживания активирован"
    echo "${GREEN}Режим обслуживания успешно активирован.${NC}"
    echo "Сайт теперь показывает страницу технического обслуживания."
}

# Отключение режима обслуживания
disable_maintenance() {
    log "Деактивация режима обслуживания"
    echo "${YELLOW}Деактивация режима обслуживания...${NC}"

    # Проверяем, активирован ли режим
    if [ ! -f "$MAINTENANCE_HTML" ]; then
        echo "${YELLOW}Режим обслуживания не активирован.${NC}"
        return 0
    fi

    # Удаление страницы обслуживания
    echo "${YELLOW}Удаление страницы обслуживания...${NC}"
    rm -f "$MAINTENANCE_HTML"

    # Восстановление оригинальной конфигурации Nginx (если используется Nginx)
    if [ -f "/etc/nginx/sites-available/admin-antizapret" ]; then
        echo "${YELLOW}Восстановление конфигурации Nginx...${NC}"
        cp /etc/nginx/sites-available/admin-antizapret /etc/nginx/sites-enabled/
        nginx -t && systemctl reload nginx
        check_error "Не удалось перезагрузить Nginx"
    fi

    # Запуск сервиса
    echo "${YELLOW}Запуск сервиса $SERVICE_NAME...${NC}"
    systemctl start $SERVICE_NAME
    check_error "Не удалось запустить сервис $SERVICE_NAME"

    log "Режим обслуживания деактивирован"
    echo "${GREEN}Режим обслуживания успешно отключен.${NC}"
    echo "Сайт снова доступен для пользователей."
}

# Проверка статуса режима обслуживания
check_maintenance_status() {
    if [ -f "$MAINTENANCE_HTML" ]; then
        echo "${YELLOW}Статус: ${RED}АКТИВИРОВАН${NC}"
        echo "Время активации: $(stat -c %y "$MAINTENANCE_HTML" | cut -d'.' -f1)"
    else
        echo "${YELLOW}Статус: ${GREEN}НЕ АКТИВИРОВАН${NC}"
    fi
    
    press_any_key
}

# Меню управления режимом обслуживания
maintenance_menu() {
    while true; do
        clear
        echo "${GREEN}┌────────────────────────────────────────────┐"
        echo "│       Режим технического обслуживания      │"
        echo "├────────────────────────────────────────────┤"
        echo "│ 1. Включить режим обслуживания             │"
        echo "│ 2. Отключить режим обслуживания            │"
        echo "│ 3. Проверить статус                        │"
        echo "│ 0. Назад                                   │"
        echo "└────────────────────────────────────────────┘${NC}"
        
        read -p "Выберите действие: " choice
        case $choice in
            1) enable_maintenance ;;
            2) disable_maintenance ;;
            3) check_maintenance_status ;;
            0) break ;;
            *) echo "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}