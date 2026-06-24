#!/bin/bash

# Выход при любой ошибке
set -e

# Цветовые коды ANSI
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Очистка экрана и приветствие
clear
echo "=== Автоматическая настройка Self-Steal со случайным шаблоном ==="
echo ""

# 2. Запрос и проверка домена
while true; do
    echo -e -n "${YELLOW}Введите ваш домен (например, mysite.com): ${NC}"
    read DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Ошибка: Домен не может быть пустым!${NC}\n"
        continue
    fi

    if [[ "$DOMAIN" =~ [а-яА-ЯёЁ] ]]; then
        echo -e "${RED}Ошибка: Домен содержит русские буквы! Нужна латиница.${NC}\n"
        continue
    fi

    if [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9](([a-zA-Z0-9-]*[a-zA-Z0-9])?)\.)+[a-zA-Z]{2,6}$ ]]; then
        echo -e "${RED}Ошибка: Неверный формат домена (пример: domain.com).${NC}\n"
        continue
    fi
    break
done

# 3. Запрос и проверка порта
while true; do
    echo -e -n "${YELLOW}Введите локальный порт для Nginx (нажмите Enter для 8443): ${NC}"
    read PORT

    if [ -z "$PORT" ]; then
        PORT="8443"
        break
    fi

    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo -e "${RED}Ошибка: Порт должен быть числом от 1 до 65535.${NC}\n"
    fi
done

# 4. Очистка экрана перед установкой
clear
echo "=== Начинаем установку и настройку Nginx... ==="
echo "Используется домен: $DOMAIN"
echo "Используется порт: $PORT"
echo ""

# 5. Обновление пакетов и установка Nginx и Git
sudo apt update
sudo apt install nginx git -y

# 6. Скачивание шаблонов напрямую из вашего репозитория
echo "Загрузка шаблонов из GitHub..."
sudo rm -rf /var/www/html/*
sudo rm -rf /tmp/selfsteal_repo

git clone --depth 1 https://github.com /tmp/selfsteal_repo

# 7. Выбор случайного шаблона
TEMPLATE_DIR="/tmp/selfsteal_repo/templates"
mapfile -t SITES < <(find "$TEMPLATE_DIR" -maxdepth 1 -mindepth 1 -type d)

if [ ${#SITES[@]} -eq 0 ]; then
    echo "Шаблоны не найдены, создаю базовую заглушку..."
    echo "<html><body><h1>Server is running.</h1></body></html>" | sudo tee /var/www/html/index.html
else
    RANDOM_INDEX=$(( RANDOM % ${#SITES[@]} ))
    SELECTED_SITE="${SITES[$RANDOM_INDEX]}"
    echo "Выбран случайный шаблон: $(basename "$SELECTED_SITE")"
    sudo cp -r "$SELECTED_SITE"/* /var/www/html/
fi

# Очистка временных файлов после копирования
sudo rm -rf /tmp/selfsteal_repo

# 8. Создание конфигурации Nginx
echo "Запись конфигурации веб-сервера..."
cat << EOF | sudo tee /etc/nginx/sites-available/default
server {
    listen 127.0.0.1:$PORT ssl;
    server_name $DOMAIN;

    ssl_certificate /root/cert/$DOMAIN/fullchain.pem;
    ssl_certificate_key /root/cert/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
EOF

# 9. Настройка прав доступа (рекурсивно, чтобы не было 403 ошибки)
echo "Настройка прав доступа..."
sudo chmod 755 /var /var/www
sudo chmod -R 755 /var/www/html

# 10. Проверка и перезапуск службы
echo "Перезапуск Nginx..."
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

clear
echo "=== НАСТРОЙКА УСПЕШНО ЗАВЕРШЕНА ==="
echo "В панели 3x-ui (блок Reality) укажите:"
echo -e "${YELLOW}Dest (Target):${NC} 127.0.0.1:$PORT"
echo -e "${YELLOW}SNI (Server Names):${NC} $DOMAIN"
