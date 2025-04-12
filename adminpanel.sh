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
REPO_URL="git@github.com:Kirito0098/AdminAntizapret-test.git"
APP_PORT="$DEFAULT_PORT"
DB_FILE="$INSTALL_DIR/users.db"
ANTIZAPRET_INSTALL_DIR="/root/antizapret"
ANTIZAPRET_INSTALL_SCRIPT="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup.sh"
NGINX_CONF_DIR="/etc/nginx/conf.d"
SSL_CERT_DIR="/etc/nginx/ssl"

# Генерируем случайный секретный ключ
SECRET_KEY=$(openssl rand -hex 32)

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

# Функция проверки ошибок
check_error() {
  if [ $? -ne 0 ]; then
    printf "%s\n" "${RED}Ошибка при выполнении: $1${NC}" >&2
    exit 1
  fi
}

# Проверка прав root
check_root() {
  if [ "$(id -u)" -ne 0; then
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
  if [ -d "$ANTIZAPRET_INSTALL_DIR" ]; then
    return 0
  else
    return 1
  fi
}

# Установка Nginx
install_nginx() {
    echo "${YELLOW}Установка Nginx...${NC}"
    apt-get install -y -qq nginx
    check_error "Не удалось установить Nginx"
    systemctl enable nginx
    systemctl start nginx
    echo "${GREEN}Nginx успешно установлен и запущен!${NC}"
}

# Генерация самоподписанного сертификата
generate_self_signed_cert() {
    domain=$1
    
    echo "${YELLOW}Генерация самоподписанного сертификата для $domain...${NC}"
    
    # Создаем директорию для сертификатов
    mkdir -p "$SSL_CERT_DIR/$domain"
    
    # Генерируем ключ и сертификат
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_CERT_DIR/$domain/privkey.pem" \
        -out "$SSL_CERT_DIR/$domain/fullchain.pem" \
        -subj "/CN=$domain" \
        -addext "subjectAltName = DNS:$domain"
    
    check_error "Не удалось сгенерировать самоподписанный сертификат"
    
    echo "${GREEN}Самоподписанный сертификат успешно создан!${NC}"
}

# Настройка Nginx в качестве прокси
setup_nginx_proxy() {
    domain=$1
    use_https=$2
    ssl_type=$3
    
    echo "${YELLOW}Настройка Nginx в качестве прокси...${NC}"
    
    if [ "$use_https" = "y" ]; then
        if [ "$ssl_type" = "selfsigned" ]; then
            # Генерируем самоподписанный сертификат
            generate_self_signed_cert "$domain"
        fi
        
        # Конфигурация с HTTPS
        cat > "$NGINX_CONF_DIR/admin-antizapret.conf" <<EOL
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate $SSL_CERT_DIR/$domain/fullchain.pem;
    ssl_certificate_key $SSL_CERT_DIR/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static/ {
        alias $INSTALL_DIR/static/;
    }
}
EOL
    else
        # Конфигурация без HTTPS
        cat > "$NGINX_CONF_DIR/admin-antizapret.conf" <<EOL
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static/ {
        alias $INSTALL_DIR/static/;
    }
}
EOL
    fi
    
    # Проверка конфигурации Nginx
    nginx -t
    check_error "Ошибка в конфигурации Nginx"
    
    systemctl reload nginx
    echo "${GREEN}Nginx успешно настроен в качестве прокси!${NC}"
}

# Установка AntiZapret-VPN
install_antizapret() {
  echo "${YELLOW}Установка AntiZapret-VPN...${NC}"
  bash <(wget --no-hsts -qO- "$ANTIZAPRET_INSTALL_SCRIPT")
  check_error "Не удалось установить AntiZapret-VPN"
  
  if check_antizapret_installed; then
    echo "${GREEN}AntiZapret-VPN успешно установлен!${NC}"
  else
    echo "${YELLOW}AntiZapret-VPN не установлен, но это не критично.${NC}"
  fi
}

# Инициализация базы данных
init_db() {
  echo "${YELLOW}Инициализация базы данных...${NC}"
  PYTHONIOENCODING=utf-8 "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py"
  check_error "Не удалось инициализировать базу данных"
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

  # Запрос доменного имени для Nginx
  read -p "Хотите использовать Nginx в качестве прокси? (y/n): " use_nginx
  if [ "$use_nginx" = "y" ]; then
    read -p "Введите доменное имя или IP-адрес сервера: " domain_name
    if [ -z "$domain_name" ]; then
      echo "${RED}Доменное имя/IP не может быть пустым!${NC}"
      exit 1
    fi
    
    read -p "Хотите настроить HTTPS? (y/n): " use_https
    if [ "$use_https" = "y" ]; then
      echo "${YELLOW}Выберите тип SSL сертификата:${NC}"
      echo "1) Let's Encrypt (необходимо доменное имя с DNS)"
      echo "2) Самоподписанный сертификат"
      read -p "Ваш выбор [1-2]: " ssl_choice
      
      case $ssl_choice in
        1)
          read -p "Введите email для Let's Encrypt: " email
          if [ -z "$email" ]; then
            echo "${RED}Email не может быть пустым!${NC}"
            exit 1
          fi
          ssl_type="letsencrypt"
          ;;
        2)
          ssl_type="selfsigned"
          ;;
        *)
          echo "${RED}Неверный выбор!${NC}"
          exit 1
          ;;
      esac
    fi
  else
    read -p "Хотите использовать HTTPS без Nginx? (y/n): " use_https
    if [ "$use_https" = "y" ]; then
        echo "${YELLOW}Настройка HTTPS без Nginx...${NC}"
        # Генерация самоподписанного сертификата
        mkdir -p "$INSTALL_DIR/ssl"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$INSTALL_DIR/ssl/privkey.pem" \
            -out "$INSTALL_DIR/ssl/fullchain.pem" \
            -subj "/CN=$(hostname)"
        
        # Добавляем SSL параметры в .env
        echo "SSL_CERT=$INSTALL_DIR/ssl/fullchain.pem" >> "$INSTALL_DIR/.env"
        echo "SSL_KEY=$INSTALL_DIR/ssl/privkey.pem" >> "$INSTALL_DIR/.env"
        echo "USE_HTTPS=true" >> "$INSTALL_DIR/.env"
    else
        echo "USE_HTTPS=false" >> "$INSTALL_DIR/.env"
    fi
  fi

  # Обновление пакетов
  echo "${YELLOW}Обновление списка пакетов...${NC}"
  apt-get update -qq
  check_error "Не удалось обновить пакеты"

  # Установка зависимостей
  echo "${YELLOW}Установка системных зависимостей...${NC}"
  apt-get install -y -qq python3 python3-pip python3-venv git wget openssl
  check_error "Не удалось установить зависимости"

  # Установка Nginx если требуется
  if [ "$use_nginx" = "y" ]; then
    install_nginx
    
    if [ "$use_https" = "y" ] && [ "$ssl_type" = "letsencrypt" ]; then
      echo "${YELLOW}Установка certbot для получения SSL сертификата...${NC}"
      apt-get install -y -qq certbot python3-certbot-nginx
      check_error "Не удалось установить certbot"
      
      echo "${YELLOW}Получение SSL сертификата для домена $domain_name...${NC}"
      certbot --nginx -d $domain_name --non-interactive --agree-tos -m $email
      check_error "Не удалось получить SSL сертификат"
      
      # Настройка автоматического обновления сертификата
      (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
      echo "${GREEN}SSL сертификат успешно установлен и настроено автоматическое обновление!${NC}"
    fi
  fi

  # Клонирование репозитория
  echo "${YELLOW}Клонирование репозитория...${NC}"
   if [ -d "$INSTALL_DIR/.git" ]; then
  echo "${YELLOW}Директория уже существует, обновляем...${NC}"
  cd "$INSTALL_DIR" && git pull
  else
    git clone "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
  fi
  check_error "Не удалось клонировать репозиторий"

  # Создание директории и копирование скрипта
  echo "${YELLOW}Копирование adminpanel.sh в /root/adminpanel/...${NC}"
  mkdir -p /root/adminpanel
  cp "$INSTALL_DIR/adminpanel.sh" /root/adminpanel/
  chmod +x /root/adminpanel/adminpanel.sh

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
  cat > "$INSTALL_DIR/.env" <<EOL
SECRET_KEY='$SECRET_KEY'
APP_PORT=$APP_PORT
EOL
  chmod 600 "$INSTALL_DIR/.env"

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

  # Настройка Nginx если требуется
  if [ "$use_nginx" = "y" ]; then
    setup_nginx_proxy "$domain_name" "$use_https" "$ssl_type"
  fi

  # Проверка установки AntiZapret-VPN
  echo "${YELLOW}Проверка установки AntiZapret-VPN...${NC}"
  sleep 3
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "${GREEN}"
    echo "┌────────────────────────────────────────────┐"
    echo "│   Установка успешно завершена!             │"
    echo "├────────────────────────────────────────────┤"
    if [ "$use_nginx" = "y" ]; then
      if [ "$use_https" = "y" ]; then
        echo "│ Адрес: https://$domain_name"
        if [ "$ssl_type" = "selfsigned" ]; then
          echo "│ ВНИМАНИЕ: Используется самоподписанный сертификат!"
          echo "│ Браузер может предупреждать о небезопасном соединении."
        fi
      else
        echo "│ Адрес: http://$domain_name"
      fi
    else
      if grep -q "USE_HTTPS=true" "$INSTALL_DIR/.env"; then
        echo "│ Адрес: https://$(hostname -I | awk '{print $1}'):$APP_PORT"
        echo "│ ВНИМАНИЕ: Используется самоподписанный сертификат!"
        echo "│ Браузер может предупреждать о небезопасном соединении."
      else
        echo "│ Адрес: http://$(hostname -I | awk '{print $1}'):$APP_PORT"
      fi
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
  echo "${YELLOW}Последние логи (Ctrl+C для выхода):${NC}"
  journalctl -u $SERVICE_NAME -n 50 -f
}

# Проверка обновлений
check_updates() {
  echo "${YELLOW}Проверка обновлений...${NC}"
  cd $INSTALL_DIR || exit 1
  git fetch
  LOCAL_HASH=$(git rev-parse HEAD)
  REMOTE_HASH=$(git rev-parse origin/main)

  if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    echo "${GREEN}Доступны обновления!${NC}"
    echo "Локальная версия: ${LOCAL_HASH:0:7}"
    echo "Удалённая версия: ${REMOTE_HASH:0:7}"
    echo -n "Установить обновления? (y/n) "
    read -r
    if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
      git pull origin main
      $VENV_PATH/bin/pip install -r requirements.txt 2>/dev/null || \
        echo "${YELLOW}Файл requirements.txt не найден, пропускаем...${NC}"
      systemctl restart $SERVICE_NAME
        cp "$INSTALL_DIR/adminpanel.sh" /root/adminpanel/
        chmod +x /root/adminpanel/adminpanel.sh
      echo "${GREEN}Обновление завершено!${NC}"
    fi
  else
    echo "${GREEN}У вас актуальная версия.${NC}"
  fi
  press_any_key
}


# Создание резервной копии
create_backup() {
  local backup_dir="/var/backups/antizapret"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="$backup_dir/backup_$timestamp.tar.gz"
  
  echo "${YELLOW}Создание резервной копии...${NC}"
  mkdir -p "$backup_dir"
  
  tar -czf "$backup_file" \
    "$INSTALL_DIR" \
    /etc/systemd/system/$SERVICE_NAME.service \
    /root/antizapret/client 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "${GREEN}Резервная копия создана: $backup_file${NC}"
    du -h "$backup_file"
  else
    echo "${RED}Ошибка при создании резервной копии!${NC}"
  fi
  press_any_key
}

# Восстановление из резервной копии
restore_backup() {
  local backup_dir="/var/backups/antizapret"
  
  echo "${YELLOW}Доступные резервные копии:${NC}"
  ls -lh "$backup_dir"/*.tar.gz 2>/dev/null || {
    echo "${RED}Резервные копии не найдены!${NC}"
    press_any_key
    return
  }
  
  read -p "Введите имя файла для восстановления: " backup_file
  
  if [ ! -f "$backup_dir/$backup_file" ]; then
    echo "${RED}Файл не найден!${NC}"
    press_any_key
    return
  fi
  
  echo "${YELLOW}Восстановление из $backup_file...${NC}"
  
  # Остановка сервиса перед восстановлением
  systemctl stop $SERVICE_NAME
  
  # Восстановление файлов
  tar -xzf "$backup_dir/$backup_file" -C /
  
  # Перезапуск сервиса
  systemctl start $SERVICE_NAME
  
  echo "${GREEN}Восстановление завершено!${NC}"
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
      
      # Остановка и удаление сервиса
      printf "%s\n" "${YELLOW}Остановка сервиса...${NC}"
      systemctl stop $SERVICE_NAME
      systemctl disable $SERVICE_NAME
      rm -f "/etc/systemd/system/$SERVICE_NAME.service"
      systemctl daemon-reload
      
      # Удаление файлов
      printf "%s\n" "${YELLOW}Удаление файлов...${NC}"
      rm -rf "$INSTALL_DIR"
      
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
  
  read -p "Введите логин администратора: " username
  while true; do
    read -s -p "Введите пароль: " password
    echo
    read -s -p "Повторите пароль: " password_confirm
    echo
    if [ "$password" != "$password_confirm" ]; then
      echo "${RED}Пароли не совпадают! Попробуйте снова.${NC}"
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
    
    # Сохраняем SECRET_KEY если он есть
    if [ -f "$INSTALL_DIR/.env" ]; then
        secret_key=$(grep '^SECRET_KEY=' "$INSTALL_DIR/.env" || echo "SECRET_KEY='$(openssl rand -hex 32)'")
    else
        secret_key="SECRET_KEY='$(openssl rand -hex 32)'"
    fi
    
    # Обновляем .env
    cat > "$INSTALL_DIR/.env" <<EOL
$secret_key
APP_PORT=$new_port
EOL
    
    chmod 600 "$INSTALL_DIR/.env"
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
    printf "│ 0. Выход                                   │\n"
    printf "└────────────────────────────────────────────┘\n"
    printf "%s\n" "${NC}"
    
    printf "Выберите действие [0-11]: "
    read choice
    case $choice in
      1) add_admin;;
      2) delete_admin;;
      3) restart_service;;
      4) check_status;;
      5) show_logs;;
      6) check_updates;;
      7) create_backup;;
      8) restore_backup;;
      9) uninstall;;
      10) check_and_set_permissions;;
      11) change_port;;
      0) exit 0;;
      *) printf "%s\n" "${RED}Неверный выбор!${NC}"; sleep 1;;
    esac
  done
}

# Главная функция
main() {
  check_root
  
  if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    printf "%s\n" "${YELLOW}AdminAntizapret не установлен.${NC}"
    printf "Хотите установить? (y/n) "
    read -r answer
    case $answer in
      [Yy]*) install; main_menu;;
      *) exit 0;;
    esac
  else
    main_menu
  fi
}

# Запуск скрипта
main "$@"
