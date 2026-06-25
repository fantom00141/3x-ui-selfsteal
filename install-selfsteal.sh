#!/bin/bash

set -e

# ==========================
# Настройки
# ==========================

github_user="fantom00141"
repo_name="3x-ui-selfsteal"

tmp_dir="/tmp/3xui-camo-installer"

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
ok()    { echo -e "${GREEN}✅ $1${RESET}"; }
err()   { echo -e "${RED}❌ $1${RESET}"; exit 1; }
info()  { echo -e "${CYAN}$1${RESET}"; }

find_free_port() {
    local p=$1
    while ss -tuln | grep -q ":${p}\b"; do
        p=$((p+1))
    done
    echo "$p"
}

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

msg "🔍 Поиск свободного порта..."
port=$(find_free_port 9443)

ok "Выбран шаблон: ${template_name}"
ok "Свободный порт: ${port}"

site_dir="/var/www/${domain}"

rm -rf "$site_dir"
mkdir -p "$site_dir"

cp -a "${template}/." "$site_dir/"

nginx_conf="/etc/nginx/conf.d/${domain}.conf"

cat > "$nginx_conf" <<EOF
server {
    listen ${port};
    server_name ${domain};

    root ${site_dir};
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log off;
}
EOF

msg "⚙ Проверка конфигурации Nginx..."
nginx -t || err "Ошибка в конфигурации Nginx."

systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx || err "Не удалось перезапустить Nginx."

rm -rf "$tmp_dir"

echo
echo -e "${GREEN}${BOLD}"
echo "========================================="
echo "        ✅ Установка завершена"
echo "========================================="
echo -e "${RESET}"

echo -e "${YELLOW}Домен:${RESET} ${GREEN}${domain}${RESET}"
echo -e "${YELLOW}Шаблон:${RESET} ${GREEN}${template_name}${RESET}"
echo -e "${YELLOW}Локальный порт Nginx:${RESET} ${GREEN}${port}${RESET}"

echo
echo -e "${CYAN}${BOLD}Настройки 3X-UI Reality${RESET}"
echo
echo -e "${YELLOW}SNI:${RESET} ${GREEN}${domain}${RESET}"
echo -e "${YELLOW}Target:${RESET} ${GREEN}127.0.0.1:${port}${RESET}"
