#!/bin/bash
# Минималистичный установщик AdminAntizapret

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Параметры установки
INSTALL_DIR="/opt/AdminAntizapret"
REPO_URL="https://github.com/Kirito0098/AdminAntizapret-test.git"
MAIN_SCRIPT="$INSTALL_DIR/adminpanel.sh"

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Ошибка: этот скрипт требует прав root!${NC}" >&2
  exit 1
fi

# Клонирование репозитория
echo -e "${YELLOW}Клонирование репозитория...${NC}"
if [ -d "$INSTALL_DIR" ]; then
  echo -e "${YELLOW}Директория уже существует, обновляем...${NC}"
  cd "$INSTALL_DIR" && git pull
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Проверка успешности клонирования
if [ ! -f "$MAIN_SCRIPT" ]; then
  echo -e "${RED}Ошибка: не удалось найти основной скрипт!${NC}" >&2
  exit 1
fi

# Установка прав
chmod +x "$MAIN_SCRIPT"

# Запуск основного скрипта
echo -e "${GREEN}Установка завершена. Запускаем основной скрипт...${NC}"
exec "$MAIN_SCRIPT"