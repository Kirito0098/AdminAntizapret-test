#!/bin/bash

source ./lib/config.sh
source ./lib/utils.sh

# Добавление администратора
add_admin() {
    echo "${YELLOW}Добавление нового администратора...${NC}"
    
    # Запрос логина
    read -p "Введите логин администратора: " username
    while [[ -z "$username" ]]; do
        echo "${RED}Логин не может быть пустым!${NC}"
        read -p "Введите логин администратора: " username
    done

    # Запрос пароля с проверкой
    while true; do
        read -s -p "Введите пароль (минимум 8 символов): " password
        echo
        read -s -p "Повторите пароль: " password_confirm
        echo
        
        if [ "$password" != "$password_confirm" ]; then
            echo "${RED}Пароли не совпадают! Попробуйте снова.${NC}"
        elif [ ${#password} -lt 8 ]; then
            echo "${RED}Пароль должен содержать минимум 8 символов!${NC}"
        else
            break
        fi
    done

    # Добавление пользователя через скрипт инициализации БД
    echo "${YELLOW}Добавление пользователя $username...${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --add-user "$username" "$password"
    
    if [ $? -eq 0 ]; then
        log "Администратор $username успешно добавлен"
        echo "${GREEN}Администратор $username успешно добавлен!${NC}"
    else
        log "Ошибка при добавлении администратора $username"
        echo "${RED}Ошибка при добавлении администратора!${NC}"
    fi
    
    press_any_key
}

# Удаление администратора
delete_admin() {
    echo "${YELLOW}Удаление администратора...${NC}"
    
    # Получение списка администраторов
    echo "${YELLOW}Список администраторов:${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --list-users
    
    if [ $? -ne 0 ]; then
        log "Ошибка при получении списка администраторов"
        echo "${RED}Ошибка при получении списка администраторов!${NC}"
        press_any_key
        return
    fi

    # Запрос логина для удаления
    read -p "Введите логин администратора для удаления: " username
    if [ -z "$username" ]; then
        echo "${RED}Логин не может быть пустым!${NC}"
        press_any_key
        return
    fi

    # Подтверждение удаления
    read -p "Вы уверены, что хотите удалить администратора $username? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Удаление отменено.${NC}"
        press_any_key
        return
    fi

    # Удаление пользователя
    echo "${YELLOW}Удаление администратора $username...${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --delete-user "$username"
    
    if [ $? -eq 0 ]; then
        log "Администратор $username успешно удалён"
        echo "${GREEN}Администратор '$username' успешно удалён!${NC}"
    else
        log "Ошибка при удалении администратора $username"
        echo "${RED}Ошибка при удалении администратора '$username'!${NC}"
    fi
    
    press_any_key
}

# Список администраторов
list_admins() {
    echo "${YELLOW}Список администраторов:${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --list-users
    
    if [ $? -ne 0 ]; then
        log "Ошибка при получении списка администраторов"
        echo "${RED}Ошибка при получении списка администраторов!${NC}"
    fi
    
    press_any_key
}

# Изменение пароля администратора
change_admin_password() {
    echo "${YELLOW}Изменение пароля администратора...${NC}"
    
    # Получение списка администраторов
    echo "${YELLOW}Список администраторов:${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --list-users
    
    if [ $? -ne 0 ]; then
        log "Ошибка при получении списка администраторов"
        echo "${RED}Ошибка при получении списка администраторов!${NC}"
        press_any_key
        return
    fi

    # Запрос логина
    read -p "Введите логин администратора: " username
    if [ -z "$username" ]; then
        echo "${RED}Логин не может быть пустым!${NC}"
        press_any_key
        return
    fi

    # Запрос нового пароля с проверкой
    while true; do
        read -s -p "Введите новый пароль (минимум 8 символов): " new_password
        echo
        read -s -p "Повторите новый пароль: " new_password_confirm
        echo
        
        if [ "$new_password" != "$new_password_confirm" ]; then
            echo "${RED}Пароли не совпадают! Попробуйте снова.${NC}"
        elif [ ${#new_password} -lt 8 ]; then
            echo "${RED}Пароль должен содержать минимум 8 символов!${NC}"
        else
            break
        fi
    done

    # Изменение пароля
    echo "${YELLOW}Изменение пароля для $username...${NC}"
    "$VENV_PATH/bin/python" "$INSTALL_DIR/init_db.py" --change-password "$username" "$new_password"
    
    if [ $? -eq 0 ]; then
        log "Пароль администратора $username успешно изменён"
        echo "${GREEN}Пароль администратора '$username' успешно изменён!${NC}"
    else
        log "Ошибка при изменении пароля администратора $username"
        echo "${RED}Ошибка при изменении пароля администратора '$username'!${NC}"
    fi
    
    press_any_key
}