#!/bin/bash

# Установочный скрипт для AdminAntizapret

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Параметры установки
REPO_URL="https://github.com/Kirito0098/AdminAntizapret-test.git"
INSTALL_DIR="/opt/AdminAntizapret"
ADMINPANEL_SCRIPT="$INSTALL_DIR/adminpanel.sh"

# Функция проверки ошибок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка: $1${NC}"
    exit 1
  fi
}

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Этот скрипт должен быть запущен с правами root!${NC}"
  exit 1
fi

# Установка необходимых пакетов
echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
apt-get update -qq
apt-get install -y -qq git wget curl > /dev/null 2>&1
check_error "Не удалось установить зависимости"

# Клонирование репозитория
echo -e "${YELLOW}Клонирование репозитория AdminAntizapret...${NC}"
if [ -d "$INSTALL_DIR" ]; then
  echo -e "${YELLOW}Директория уже существует, обновляем...${NC}"
  cd "$INSTALL_DIR" && git pull origin main > /dev/null 2>&1
else
  git clone --quiet "$REPO_URL" "$INSTALL_DIR" > /dev/null
fi
check_error "Не удалось клонировать репозиторий"

# Настройка прав
echo -e "${YELLOW}Настройка прав доступа...${NC}"
chown -R root:root "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
chmod +x "$ADMINPANEL_SCRIPT" "$INSTALL_DIR/client.sh"


# Запуск панели управления
echo -e "${GREEN}Установка завершена! Запуск панели управления...${NC}"
sleep 2
cd "$INSTALL_DIR" && bash "$ADMINPANEL_SCRIPT" --install