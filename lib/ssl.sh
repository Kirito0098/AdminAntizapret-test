#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Установка Nginx с Let's Encrypt
setup_nginx_letsencrypt() {
    log "Настройка Nginx + Let's Encrypt для домена $DOMAIN"
    echo "${YELLOW}Установка Nginx и Let's Encrypt...${NC}"
    
    # Удаление существующих iptables правил перед получением сертификата
    echo "${YELLOW}Удаление iptables правил перенаправления портов...${NC}"
    iptables -t nat -D PREROUTING -i ens3 -p tcp --dport 80 -j REDIRECT --to-port 50080 2>/dev/null || true
    iptables -t nat -D PREROUTING -i ens3 -p tcp --dport 443 -j REDIRECT --to-port 50443 2>/dev/null || true
    iptables -t nat -D PREROUTING -i ens3 -p udp --dport 80 -j REDIRECT --to-port 50080 2>/dev/null || true
    iptables -t nat -D PREROUTING -i ens3 -p udp --dport 443 -j REDIRECT --to-port 50443 2>/dev/null || true
    
    # Установка Nginx
    apt-get install -y -qq nginx >/dev/null 2>&1
    check_error "Не удалось установить Nginx"
    
    # Установка Certbot
    apt-get install -y -qq certbot python3-certbot-nginx >/dev/null 2>&1
    check_error "Не удалось установить Certbot"
    
    # Настройка Nginx
    cat > /etc/nginx/sites-available/admin-antizapret <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
    
    ln -s /etc/nginx/sites-available/admin-antizapret /etc/nginx/sites-enabled/
    systemctl restart nginx
    
    # Получение сертификата
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL
    check_error "Не удалось получить сертификат Let's Encrypt"
    
    # Удаляем старый файл с SSL-параметрами, чтобы избежать дублирования
    rm -f /etc/nginx/conf.d/ssl-params.conf
    
    # Настройка SSL параметров - только то, что не устанавливается certbot по умолчанию
    cat > /etc/nginx/conf.d/ssl-params.conf <<EOL
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOL
    
    # Настройка автоматического обновления
    (crontab -l 2>/dev/null; echo "0 60 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    # Проверяем конфигурацию и перезапускаем Nginx
    nginx -t && systemctl restart nginx
    
    # Настройка конфигурации Flask для HTTPS
    if [ -f "$INSTALL_DIR/.env" ]; then
        echo "${YELLOW}.env файл существует, добавляем HTTPS параметры...${NC}"
        grep -qxF "USE_HTTPS=true" "$INSTALL_DIR/.env" || echo "USE_HTTPS=true" >> "$INSTALL_DIR/.env"
    else
        echo "${YELLOW}Создание .env файла с HTTPS параметрами...${NC}"
        echo "USE_HTTPS=true" > "$INSTALL_DIR/.env"
    fi
    
    log "Nginx с Let's Encrypt успешно настроен"
    echo "${GREEN}Nginx с Let's Encrypt успешно настроен!${NC}"
}

# Установка с самоподписанным сертификатом
setup_selfsigned() {
    log "Настройка самоподписанного сертификата"
    echo "${YELLOW}Настройка самоподписанного сертификата...${NC}"
    
    # Создание сертификата
    mkdir -p /etc/ssl/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/admin-antizapret.key \
        -out /etc/ssl/certs/admin-antizapret.crt \
        -subj "/CN=$(hostname)" >/dev/null 2>&1
    
    # Настройка конфигурации Flask для HTTPS
    if [ -f "$INSTALL_DIR/.env" ]; then
        echo "${YELLOW}.env файл существует, добавляем значения, если их нет...${NC}"
        
        grep -qxF "USE_HTTPS=true" "$INSTALL_DIR/.env" || echo "USE_HTTPS=true" >> "$INSTALL_DIR/.env"
        grep -qxF "SSL_CERT=/etc/ssl/certs/admin-antizapret.crt" "$INSTALL_DIR/.env" || echo "SSL_CERT=/etc/ssl/certs/admin-antizapret.crt" >> "$INSTALL_DIR/.env"
        grep -qxF "SSL_KEY=/etc/ssl/private/admin-antizapret.key" "$INSTALL_DIR/.env" || echo "SSL_KEY=/etc/ssl/private/admin-antizapret.key" >> "$INSTALL_DIR/.env"
    else
        echo "${YELLOW}.env файл не найден, создаем новый...${NC}"
        cat > "$INSTALL_DIR/.env" <<EOL
USE_HTTPS=true
SSL_CERT=/etc/ssl/certs/admin-antizapret.crt
SSL_KEY=/etc/ssl/private/admin-antizapret.key
EOL
    fi
    
    log "Самоподписанный сертификат создан"
    echo "${GREEN}Самоподписанный сертификат успешно создан!${NC}"
}

# Валидация домена
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "${RED}Неверный формат домена!${NC}"
        return 1
    fi
    return 0
}

# Проверка DNS
check_dns() {
    if ! dig +short $DOMAIN | grep -q '[0-9]'; then
        echo "${YELLOW}DNS запись для $DOMAIN не найдена или неверна!${NC}"
        return 1
    fi
    return 0
}

# Изменение порта сервиса
change_port() {
    echo "${YELLOW}Изменение порта сервиса...${NC}"
    
    # Получение текущего порта
    current_port=$(grep "APP_PORT=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
    echo "Текущий порт: $current_port"
    
    # Запрос нового порта
    read -p "Введите новый порт: " new_port
    
    # Проверка валидности порта
    if ! [[ $new_port =~ ^[0-9]+$ ]] || [ $new_port -lt 1 ] || [ $new_port -gt 65535 ]; then
        echo "${RED}Неверный номер порта! Должен быть от 1 до 65535.${NC}"
        return 1
    fi
    
    # Проверка занятости порта
    if check_port $new_port; then
        echo "${RED}Порт $new_port уже занят!${NC}"
        return 1
    fi
    
    # Обновление конфигурации
    sed -i "s/APP_PORT=$current_port/APP_PORT=$new_port/" "$INSTALL_DIR/.env"
    
    # Обновление конфигурации Nginx, если используется
    if [ -f "/etc/nginx/sites-available/admin-antizapret" ]; then
        sed -i "s/proxy_pass http:\/\/127.0.0.1:$current_port/proxy_pass http:\/\/127.0.0.1:$new_port/" /etc/nginx/sites-available/admin-antizapret
        nginx -t && systemctl reload nginx
    fi
    
    # Перезапуск сервиса
    systemctl restart $SERVICE_NAME
    
    echo "${GREEN}Порт успешно изменен на $new_port!${NC}"
    press_any_key
}