#!/bin/bash

set -e

# ==========================
# Настройки
# ==========================

github_user="fantom00141"
repo_name="3x-ui-selfsteal"
repo_branch="94e8ffa80c4b376e360148bd803b6ea51af52542"

tmp_dir="/tmp/3xui-camo-installer"
site_dir="/var/www/html"

# ==========================
# Цвета
# ==========================

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

msg()   { echo -e "${YELLOW}$1${RESET}"; }
ok()    { echo -e "${GREEN}✓ $1${RESET}"; }
err()   { echo -e "${RED}✗ $1${RESET}"; exit 1; }
info()  { echo -e "${CYAN}$1${RESET}"; }

clear
echo -e "${CYAN}${BOLD}"
echo "========================================="
echo "      3XUI SelfSteal Installer"
echo "========================================="
echo -e "${RESET}"

[ "$EUID" -eq 0 ] || err "Запустите скрипт от root."

export DEBIAN_FRONTEND=noninteractive

msg "📦 Обновление списка пакетов..."
apt update -y

for p in git curl wget unzip ca-certificates nginx; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
        msg "Установка $p..."
        apt install -y "$p"
    fi
done

while true; do
    msg "🌐 Введите домен:"
    read -r domain

    if [[ "$domain" =~ ^([A-Za-z0-9][-A-Za-z0-9]*\.)+[A-Za-z]{2,}$ ]]; then
        break
    fi

    echo -e "${RED}Неверный формат домена.${RESET}"
done

# Выбор порта
echo
msg "🔌 Выберите порт для Nginx:"
echo "1) 9443 (по умолчанию)"
echo "2) Ввести свой порт"
read -r port_choice

case $port_choice in
    1)
        nginx_port="9443"
        ;;
    2)
        while true; do
            msg "Введите номер порта (1024-65535):"
            read -r custom_port
            
            if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
                # Проверяем, не занят ли порт
                if ss -tuln | grep -q ":${custom_port}\b"; then
                    echo -e "${RED}Порт ${custom_port} уже занят. Выберите другой.${RESET}"
                else
                    nginx_port="$custom_port"
                    break
                fi
            else
                echo -e "${RED}Неверный порт. Введите число от 1024 до 65535.${RESET}"
            fi
        done
        ;;
    *)
        nginx_port="9443"
        msg "Используем порт по умолчанию: 9443"
        ;;
esac

ok "Выбран порт: ${nginx_port}"

msg "📥 Загрузка репозитория..."
rm -rf "$tmp_dir"

git clone --depth 1 \
"https://github.com/${github_user}/${repo_name}.git" \
"$tmp_dir" || err "Не удалось скачать репозиторий."

templates_dir="${tmp_dir}/templates"

[ -d "$templates_dir" ] || err "Папка templates не найдена."

mapfile -t templates < <(find "$templates_dir" -mindepth 1 -maxdepth 1 -type d | sort)

[ "${#templates[@]}" -gt 0 ] || err "Шаблоны не найдены."

echo
msg "Выберите режим:"
echo "1) Выбрать шаблон"
echo "2) Случайный шаблон"
read -r mode

if [ "$mode" = "1" ]; then
    echo
    for i in "${!templates[@]}"; do
        echo "$((i+1))) $(basename "${templates[$i]}")"
    done

    while true; do
        echo
        msg "Введите номер шаблона:"
        read -r n

        if [[ "$n" =~ ^[0-9]+$ ]] &&
           [ "$n" -ge 1 ] &&
           [ "$n" -le "${#templates[@]}" ]; then
            template="${templates[$((n-1))]}"
            break
        fi

        echo -e "${RED}Неверный выбор.${RESET}"
    done
else
    template=$(printf "%s\n" "${templates[@]}" | shuf -n1)
fi

template_name=$(basename "$template")

ok "Выбран шаблон: ${template_name}"

# Создаем директорию если её нет
mkdir -p "$site_dir"

# Очищаем директорию
rm -rf "${site_dir:?}"/*

# Копируем файлы шаблона в /var/www/html/
cp -r "${template}/." "$site_dir/"

# Путь к конфигурации Nginx
nginx_conf="/etc/nginx/sites-available/default"

# Проверяем, существует ли файл конфигурации
if [ -f "$nginx_conf" ]; then
    # Создаем бэкап с датой
    backup_name="${nginx_conf}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$nginx_conf" "$backup_name"
    ok "Создан бэкап: ${backup_name}"
fi

# Создаем новую конфигурацию
cat > "$nginx_conf" <<EOF
server {
    # Слушаем только локально
    listen 127.0.0.1:${nginx_port} ssl;
    server_name ${domain};

    # Ваши готовые сертификаты
    ssl_certificate /root/cert/${domain}/fullchain.pem;
    ssl_certificate_key /root/cert/${domain}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Статический сайт
    location / {
        root /var/www/html;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
}
EOF

msg "⚙ Проверка конфигурации Nginx..."
nginx -t || err "Ошибка в конфигурации Nginx."

# Устанавливаем правильные права доступа
msg "🔧 Настройка прав доступа..."
sudo chmod 755 /var /var/www /var/www/html 2>/dev/null || true
sudo chmod 644 /var/www/html/* 2>/dev/null || true
sudo chmod -R 755 /var/www/html 2>/dev/null || true

# Перезапускаем Nginx
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx || err "Не удалось перезапустить Nginx."
systemctl reload nginx || err "Не удалось перезагрузить Nginx."

# Проверяем, что порт слушается
sleep 2
if ss -tuln | grep -q ":${nginx_port}\b"; then
    ok "Nginx успешно запущен на порту ${nginx_port}"
else
    msg "⚠ Внимание: порт ${nginx_port} не обнаружен в прослушивании"
fi

# Очистка
rm -rf "$tmp_dir"

echo
echo -e "${GREEN}${BOLD}"
echo "========================================="
echo "        ✓ Установка завершена"
echo "========================================="
echo -e "${RESET}"

echo -e "${YELLOW}Домен:${RESET} ${GREEN}${domain}${RESET}"
echo -e "${YELLOW}Шаблон:${RESET} ${GREEN}${template_name}${RESET}"
echo -e "${YELLOW}Путь к файлам:${RESET} ${GREEN}${site_dir}${RESET}"
echo -e "${YELLOW}Порт Nginx:${RESET} ${GREEN}${nginx_port}${RESET}"

echo
echo -e "${CYAN}${BOLD}Настройки 3X-UI Reality${RESET}"
echo
echo -e "${YELLOW}SNI:${RESET} ${GREEN}${domain}${RESET}"
echo -e "${YELLOW}Target:${RESET} ${GREEN}127.0.0.1:${nginx_port}${RESET}"
echo
echo -e "${YELLOW}Путь к сертификатам:${RESET} ${GREEN}/root/cert/${domain}/${RESET}"
echo
echo -e "${CYAN}Проверка статуса Nginx:${RESET}"
systemctl status nginx --no-pager | head -n 5
