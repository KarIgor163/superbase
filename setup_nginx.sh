#!/bin/bash

# Скрипт для настройки Nginx как обратного прокси для Supabase
set -e

echo "🚀 Настройка Nginx для Supabase..."

# Проверка наличия sudo прав
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт требует привилегий суперпользователя. Используйте sudo."
   exit 1
fi

# Установка Nginx
echo "📦 Установка Nginx..."
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx

# Запрос домена
read -p "Введите домен для Supabase (например, supabase.example.com): " DOMAIN

# Создание конфига Nginx
echo "⚙️ Настройка конфигурации Nginx..."
CONFIG_PATH="/etc/nginx/sites-available/supabase"

cat > $CONFIG_PATH << EOL
server {
    listen 80;
    server_name $DOMAIN;

    # Проксирование Supabase Studio
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Проксирование REST API
    location /rest/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Проксирование Realtime API
    location /realtime/ {
        proxy_pass http://localhost:4000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOL

# Активация конфига
ln -sf $CONFIG_PATH /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "✅ Nginx настроен для Supabase."

# Запрос на установку SSL
read -p "Хотите настроить SSL с Let's Encrypt? (y/n): " SETUP_SSL

if [ "$SETUP_SSL" = "y" ] || [ "$SETUP_SSL" = "Y" ]; then
    echo "🔒 Настройка SSL с Let's Encrypt..."
    certbot --nginx -d $DOMAIN
    
    echo "✅ SSL сертификат установлен!"
    echo "🔄 Не забудьте обновить SITE_URL в конфигурации Supabase (.env) на https://$DOMAIN"
    echo "   и перезапустить контейнеры: docker-compose -f /opt/supabase/docker-compose.yml restart"
fi

echo "
📊 Supabase теперь доступен по адресу: http://$DOMAIN
" 