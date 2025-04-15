#!/bin/bash

# Установочный скрипт для AdminAntizapret
# Автоматически клонирует репозиторий, настраивает права и запускает панель управления

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
apt-get install -y -qq git wget curl > /dev/null
check_error "Не удалось установить зависимости"

# Клонирование репозитория
echo -e "${YELLOW}Клонирование репозитория AdminAntizapret...${NC}"
if [ -d "$INSTALL_DIR" ]; then
  echo -e "${YELLOW}Директория уже существует, обновляем...${NC}"
  cd "$INSTALL_DIR" && git pull origin main
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
check_error "Не удалось клонировать репозиторий"

# Настройка прав
echo -e "${YELLOW}Настройка прав доступа...${NC}"
chown -R root:root "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
chmod +x "$ADMINPANEL_SCRIPT" "$INSTALL_DIR/client.sh"

# Установка Python зависимостей
echo -e "${YELLOW}Установка Python зависимостей...${NC}"
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null
check_error "Не удалось установить Python"

# Создание виртуального окружения
python3 -m venv "$INSTALL_DIR/venv"
check_error "Не удалось создать виртуальное окружение"

# Установка pip пакетов
"$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
check_error "Не удалось установить Python зависимости"

# Запуск панели управления
echo -e "${GREEN}Установка завершена! Запуск панели управления...${NC}"
sleep 2
cd "$INSTALL_DIR" && bash "$ADMINPANEL_SCRIPT" --install