#!/bin/bash

# Выход при любой ошибке
set -e

echo "=== Автоматическая настройка Self-Steal со случайным шаблоном ==="

# 1. Запрос данных у пользователя
read -p "Введите ваш домен (например, mysite.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "Ошибка: Домен не может быть пустым."
    exit 1
fi

read -p "Введите локальный порт для Nginx (например, 8443): " PORT
if [ -z "$PORT" ]; then
    PORT="8443"
fi
echo "Используется порт: $PORT"

# 2. Обновление пакетов и установка необходимых утилит
echo "Установка Nginx и дополнительных утилит..."
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
