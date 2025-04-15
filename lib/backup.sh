#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Создание резервной копии
create_backup() {
    local backup_dir="/var/backups/antizapret"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/full_backup_$timestamp.tar.gz"
    
    log "Создание резервной копии в $backup_file"
    echo "${YELLOW}Создание полной резервной копии...${NC}"
    
    # Создание директории для бэкапов, если её нет
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
    
    # Список включаемых в бэкап файлов и директорий
    local include_files=(
        "$INSTALL_DIR"
        "/etc/systemd/system/$SERVICE_NAME.service"
        "$DB_FILE"
    )
    
    # Добавление SSL сертификатов, если они существуют
    [ -f "/etc/ssl/certs/admin-antizapret.crt" ] && include_files+=( "/etc/ssl/certs/admin-antizapret.crt" )
    [ -f "/etc/ssl/private/admin-antizapret.key" ] && include_files+=( "/etc/ssl/private/admin-antizapret.key" )
    
    # Добавление конфигурации Nginx, если она существует
    [ -f "/etc/nginx/sites-available/admin-antizapret" ] && include_files+=( "/etc/nginx/sites-available/admin-antizapret" )
    [ -f "/etc/nginx/sites-enabled/admin-antizapret" ] && include_files+=( "/etc/nginx/sites-enabled/admin-antizapret" )
    
    # Добавление Let's Encrypt сертификатов, если они существуют
    if [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        include_files+=( "/etc/letsencrypt/live/$DOMAIN" )
        include_files+=( "/etc/letsencrypt/archive/$DOMAIN" )
        include_files+=( "/etc/letsencrypt/renewal/$DOMAIN.conf" )
    fi
    
    # Создание архива
    echo "${YELLOW}Архивирование данных...${NC}"
    tar -czf "$backup_file" "${include_files[@]}" 2>/dev/null
    
    # Проверка целостности архива
    if ! tar -tzf "$backup_file" >/dev/null; then
        log "Ошибка: резервная копия повреждена"
        echo "${RED}Ошибка: резервная копия повреждена!${NC}"
        rm -f "$backup_file"
        return 1
    fi
    
    # Защита резервной копии
    chmod 600 "$backup_file"
    
    # Вывод информации о созданном бэкапе
    local backup_size=$(du -h "$backup_file" | cut -f1)
    log "Резервная копия создана: $backup_file ($backup_size)"
    
    echo "${GREEN}Резервная копия успешно создана:${NC}"
    echo "Файл: $backup_file"
    echo "Размер: $backup_size"
    echo "Содержимое:"
    tar -tzf "$backup_file" | sed 's/^/  /'
    
    # Рекомендация по восстановлению
    echo -e "\n${YELLOW}Для восстановления используйте команду:${NC}"
    echo "$0 --restore $backup_file"
    
    return 0
}

# Восстановление из резервной копии
restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        log "Файл резервной копии не найден: $backup_file"
        echo "${RED}Файл резервной копии не найден!${NC}"
        return 1
    fi
    
    # Проверка целостности архива перед восстановлением
    if ! tar -tzf "$backup_file" >/dev/null; then
        log "Ошибка: резервная копия повреждена: $backup_file"
        echo "${RED}Ошибка: резервная копия повреждена!${NC}"
        return 1
    fi
    
    log "Восстановление из резервной копии $backup_file"
    echo "${YELLOW}Подготовка к восстановлению из резервной копии...${NC}"
    
    # Просмотр содержимого бэкапа
    echo "${YELLOW}Содержимое резервной копии:${NC}"
    tar -tzf "$backup_file" | sed 's/^/  /'
    echo
    
    # Подтверждение восстановления
    read -p "Вы уверены, что хотите восстановить систему из этой резервной копии? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Восстановление отменено.${NC}"
        return 0
    fi
    
    echo "${YELLOW}Начало восстановления...${NC}"
    
    # Остановка сервисов перед восстановлением
    echo "${YELLOW}Остановка сервисов...${NC}"
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl stop nginx 2>/dev/null
    
    # Восстановление файлов
    echo "${YELLOW}Восстановление файлов...${NC}"
    tar -xzf "$backup_file" -C /
    
    # Восстановление прав доступа
    chown -R root:root "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"
    chmod 700 "$DB_FILE"
    
    # Перезапуск сервисов
    echo "${YELLOW}Перезапуск сервисов...${NC}"
    systemctl daemon-reload
    systemctl start "$SERVICE_NAME"
    
    # Перезапуск Nginx, если он был установлен
    if [ -f "/etc/nginx/sites-available/admin-antizapret" ]; then
        nginx -t && systemctl start nginx
    fi
    
    log "Восстановление завершено из $backup_file"
    echo "${GREEN}Восстановление завершено успешно!${NC}"
    
    # Проверка статуса сервиса
    echo -e "\n${YELLOW}Статус сервиса:${NC}"
    systemctl status "$SERVICE_NAME" --no-pager -l
    
    return 0
}

# Список доступных резервных копий
list_backups() {
    local backup_dir="/var/backups/antizapret"
    
    if [ ! -d "$backup_dir" ]; then
        echo "${YELLOW}Директория с резервными копиями не найдена.${NC}"
        return 1
    fi
    
    local backups=($(ls -1t "$backup_dir"/full_backup_*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo "${YELLOW}Резервные копии не найдены.${NC}"
        return 1
    fi
    
    echo "${GREEN}Доступные резервные копии:${NC}"
    echo "----------------------------------------"
    
    for backup in "${backups[@]}"; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1)
        local time=$(stat -c %y "$backup" | cut -d' ' -f2 | cut -d'.' -f1)
        
        echo "Файл: $(basename "$backup")"
        echo "Размер: $size"
        echo "Дата создания: $date в $time"
        echo "----------------------------------------"
    done
    
    return 0
}