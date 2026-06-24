#!/bin/bash

# Цветовые коды ANSI
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color (Сброс цвета)

# Выход при любой ошибке (кроме проверок в цикле)
set -e

# Очищаем консоль перед началом работы
clear

echo "=== Автоматическая настройка Self-Steal со случайным шаблоном ==="
echo ""

# 1. Запрос и проверка домена
while true; do
    echo -e -n "${YELLOW}Введите ваш домен (например, mysite.com): ${NC}"
    read DOMAIN

    # Проверка 1: Пустой ввод
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Ошибка: Домен не может быть пустым! Попробуйте снова.${NC}\n"
        continue
    fi

    # Проверка 2: Наличие русских букв (кириллицы)
    if [[ "$DOMAIN" =~ [а-яА-ЯёЁ] ]]; then
        echo -e "${RED}Ошибка: Домен содержит русские буквы! Reality требует латиницу (Punycode не поддерживается встроенной автоматикой).${NC}\n"
        continue
    fi

    # Проверка 3: Валидация формата домена через регулярное выражение (минимум одна точка, без спецсимволов)
    # Шаблон проверяет: буквы/цифры/дефис . зона от 2 до 6 букв
    if [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9](([a-zA-Z0-9-]*[a-zA-Z0-9])?)\.)+[a-zA-Z]{2,6}$ ]]; then
        echo -e "${RED}Ошибка: Неверный формат домена (пример правильного: mysite.com или vpn.domain.xyz). Попробуйте снова.${NC}\n"
        continue
    fi

    # Если все проверки пройдены — выходим из цикла
    break
done

# 2. Запрос и проверка порта
while true; do
    echo -e -n "${YELLOW}Введите локальный порт для Nginx (нажмите Enter для 8443): ${NC}"
    read PORT

    # Если порт не введен, ставим по умолчанию 8443
    if [ -z "$PORT" ]; then
        PORT="8443"
        break
    fi

    # Проверка: является ли ввод числом и входит ли в диапазон портов 1-65535
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo -e "${RED}Ошибка: Порт должен быть числом от 1 до 65535.${NC}\n"
    fi
done

echo "Используется порт: $PORT"
echo ""

# Очищаем консоль перед запуском установки
clear
echo "${YELLOW}=== Начинаем установку и настройку Nginx... ===${NC}"
sudo apt update
sudo apt install nginx curl git subversion -y

# 3. Скачивание и выбор случайного шаблона
echo "Подготовка маскировочного сайта..."
sudo rm -rf /var/www/html/*
sudo mkdir -p /tmp/templates

# Скачиваем только папку templates из вашего репозитория через SVN (чтобы не клонировать весь git со служебными файлами)
sudo rm -rf /tmp/templates_download
svn export https://github.com /tmp/templates_download --force

# Получаем список всех папок-шаблонов во временной директории
mapfile -t SITES < <(find /tmp/templates_download -maxdepth 1 -mindepth 1 -type d)

if [ ${#SITES[@]} -eq 0 ]; then
    echo "Ошибка: В папке templates на GitHub не найдено подпапок с шаблонами!"
    echo "Создаю стандартную заглушку..."
    echo "<html><body><h1>Server is running.</h1></body></html>" | sudo tee /var/www/html/index.html
else
    # Выбираем случайный индекс из массива папок
    RANDOM_INDEX=$(( RANDOM % ${#SITES[@]} ))
    SELECTED_SITE="${SITES[$RANDOM_INDEX]}"
    
    echo "Выбран случайный шаблон: $(basename "$SELECTED_SITE")"
    
    # Копируем содержимое выбранной папки в рабочую директорию веб-сервера
    sudo cp -r "$SELECTED_SITE"/* /var/www/html/
fi

# Очищаем временные файлы
sudo rm -rf /tmp/templates_download

# 4. Создание конфигурационного файла Nginx
echo "Настройка конфигурации Nginx..."
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

# 5. Исправление прав доступа (рекурсивно)
echo "Настройка прав доступа для Nginx..."
sudo chmod 755 /var /var/www
sudo chmod -R 755 /var/www/html

# 6. Проверка и перезапуск Nginx
echo "Тестирование и перезапуск Nginx..."
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "=== Настройка успешно завершена! ==="
echo "Настройки для панели 3x-ui (блок Reality):"
echo "1. Dest (Target): 127.0.0.1:$PORT"
echo "2. SNI (Server Names): $DOMAIN"
