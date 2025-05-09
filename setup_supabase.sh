#!/bin/bash

# Скрипт для автоматического развертывания Supabase на VPS через Docker
set -e

echo "🚀 Начинаем установку Supabase..."

# Проверка наличия sudo прав
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт требует привилегий суперпользователя. Используйте sudo."
   exit 1
fi

# Установка необходимых зависимостей
echo "📦 Установка необходимых пакетов..."
apt-get update
apt-get install -y git docker.io docker-compose curl openssl ufw

# Запуск Docker
echo "🐳 Запуск Docker..."
systemctl enable docker
systemctl start docker

# Создание рабочей директории
echo "📁 Создание директорий проекта..."
SUPABASE_DIR="/opt/supabase"
mkdir -p $SUPABASE_DIR
cd $SUPABASE_DIR

# Клонирование репозитория Supabase
echo "📥 Клонирование репозитория Supabase..."
git clone --depth 1 https://github.com/supabase/supabase.git temp
cp -r temp/docker/* .
cp temp/docker/.env.example .env
rm -rf temp

# Генерация секретных ключей
echo "🔑 Генерация JWT секрета и ключей..."
JWT_SECRET=$(openssl rand -base64 32)
ANON_KEY=$(openssl rand -base64 32)
SERVICE_ROLE_KEY=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 16)

# Получение IP-адреса сервера
SERVER_IP=$(curl -s ifconfig.me)
SITE_URL="http://$SERVER_IP"

# Конфигурация переменных окружения
echo "⚙️ Настройка переменных окружения..."
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
sed -i "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env
sed -i "s|SITE_URL=.*|SITE_URL=$SITE_URL|" .env

# Настройка фаервола (UFW)
echo "🛡️ Настройка фаервола..."
ufw allow 22/tcp
ufw allow 8000/tcp    # Supabase Studio
ufw allow 5432/tcp    # PostgreSQL
ufw allow 3000/tcp    # API
ufw allow 4000/tcp    # Realtime
ufw allow 80,443/tcp  # HTTP/HTTPS
ufw --force enable
ufw reload

# Запуск Supabase
echo "🏁 Запуск Supabase..."
docker-compose pull
docker-compose up -d

# Проверка статуса
echo "🔍 Проверка статуса контейнеров..."
docker-compose ps

echo "
✅ Установка Supabase успешно завершена!
📊 Доступ к Supabase Studio: http://$SERVER_IP:8000

Сохраните следующие данные:
📝 POSTGRES_PASSWORD: $POSTGRES_PASSWORD
📝 JWT_SECRET: $JWT_SECRET
📝 ANON_KEY: $ANON_KEY
📝 SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY

Полезные команды:
- Остановить: docker-compose -f $SUPABASE_DIR/docker-compose.yml down
- Перезапустить: docker-compose -f $SUPABASE_DIR/docker-compose.yml restart
- Логи: docker-compose -f $SUPABASE_DIR/docker-compose.yml logs -f
"

# Сохранение данных в файл
cat > $SUPABASE_DIR/supabase_credentials.txt << EOL
SUPABASE CREDENTIALS
====================
POSTGRES_PASSWORD: $POSTGRES_PASSWORD
JWT_SECRET: $JWT_SECRET
ANON_KEY: $ANON_KEY
SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY
SITE_URL: $SITE_URL
====================
Дата установки: $(date)
EOL

chmod 600 $SUPABASE_DIR/supabase_credentials.txt
echo "📄 Данные для доступа сохранены в файл: $SUPABASE_DIR/supabase_credentials.txt" 