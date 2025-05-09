#!/bin/bash

# Главный скрипт-установщик Supabase с меню выбора действий
set -e

# Цвета для текста
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка наличия sudo прав
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}Этот скрипт требует привилегий суперпользователя. Используйте sudo.${NC}"
   exit 1
fi

# Директории для скриптов и проекта
SCRIPTS_DIR="/opt/supabase-scripts"
SUPABASE_DIR="/opt/supabase"

# Проверка установки Supabase
check_supabase_installed() {
    if [ -d "$SUPABASE_DIR" ] && [ -f "$SUPABASE_DIR/.env" ]; then
        return 0 # установлен
    else
        return 1 # не установлен
    fi
}

# Действие: Установка Supabase
install_supabase() {
    echo -e "${BLUE}🚀 Начинаем установку Supabase...${NC}"
    
    # Проверка, установлен ли уже Supabase
    if check_supabase_installed; then
        echo -e "${YELLOW}⚠️ Supabase уже установлен в $SUPABASE_DIR${NC}"
        read -p "Хотите переустановить? (y/n): " REINSTALL
        if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
            echo "Операция отменена."
            return
        fi
    fi
    
    # Установка необходимых зависимостей
    echo -e "${BLUE}📦 Установка необходимых пакетов...${NC}"
    apt-get update
    apt-get install -y git docker.io docker-compose curl openssl ufw
    
    # Запуск Docker
    echo -e "${BLUE}🐳 Запуск Docker...${NC}"
    systemctl enable docker
    systemctl start docker
    
    # Создание рабочей директории
    echo -e "${BLUE}📁 Создание директорий проекта...${NC}"
    mkdir -p $SUPABASE_DIR
    cd $SUPABASE_DIR
    
    # Клонирование репозитория Supabase
    echo -e "${BLUE}📥 Клонирование репозитория Supabase...${NC}"
    git clone --depth 1 https://github.com/supabase/supabase.git temp
    cp -r temp/docker/* .
    cp temp/docker/.env.example .env
    rm -rf temp
    
    # Генерация секретных ключей
    echo -e "${BLUE}🔑 Генерация JWT секрета и ключей...${NC}"
    JWT_SECRET=$(openssl rand -base64 32)
    ANON_KEY=$(openssl rand -base64 32)
    SERVICE_ROLE_KEY=$(openssl rand -base64 32)
    POSTGRES_PASSWORD=$(openssl rand -base64 16)
    
    # Получение IP-адреса сервера
    SERVER_IP=$(curl -s ifconfig.me)
    SITE_URL="http://$SERVER_IP"
    
    # Конфигурация переменных окружения
    echo -e "${BLUE}⚙️ Настройка переменных окружения...${NC}"
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
    sed -i "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
    sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env
    sed -i "s|SITE_URL=.*|SITE_URL=$SITE_URL|" .env
    
    # Настройка фаервола (UFW)
    echo -e "${BLUE}🛡️ Настройка фаервола...${NC}"
    ufw allow 22/tcp
    ufw allow 8000/tcp    # Supabase Studio
    ufw allow 5432/tcp    # PostgreSQL
    ufw allow 3000/tcp    # API
    ufw allow 4000/tcp    # Realtime
    ufw allow 80,443/tcp  # HTTP/HTTPS
    ufw --force enable
    ufw reload
    
    # Запуск Supabase
    echo -e "${BLUE}🏁 Запуск Supabase...${NC}"
    docker-compose pull
    docker-compose up -d
    
    # Проверка статуса
    echo -e "${BLUE}🔍 Проверка статуса контейнеров...${NC}"
    docker-compose ps
    
    echo -e "
${GREEN}✅ Установка Supabase успешно завершена!${NC}
${GREEN}📊 Доступ к Supabase Studio: http://$SERVER_IP:8000${NC}

${YELLOW}Сохраните следующие данные:${NC}
📝 POSTGRES_PASSWORD: $POSTGRES_PASSWORD
📝 JWT_SECRET: $JWT_SECRET
📝 ANON_KEY: $ANON_KEY
📝 SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY
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
    echo -e "${GREEN}📄 Данные для доступа сохранены в файл: $SUPABASE_DIR/supabase_credentials.txt${NC}"
}

# Действие: Настройка Nginx
setup_nginx() {
    echo -e "${BLUE}🚀 Настройка Nginx для Supabase...${NC}"
    
    # Проверка, установлен ли Supabase
    if ! check_supabase_installed; then
        echo -e "${RED}❌ Supabase не установлен. Сначала установите Supabase.${NC}"
        return
    fi
    
    # Установка Nginx
    echo -e "${BLUE}📦 Установка Nginx...${NC}"
    apt-get update
    apt-get install -y nginx certbot python3-certbot-nginx
    
    # Запрос домена
    read -p "Введите домен для Supabase (например, supabase.example.com): " DOMAIN
    
    # Создание конфига Nginx
    echo -e "${BLUE}⚙️ Настройка конфигурации Nginx...${NC}"
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
    
    echo -e "${GREEN}✅ Nginx настроен для Supabase.${NC}"
    
    # Запрос на установку SSL
    read -p "Хотите настроить SSL с Let's Encrypt? (y/n): " SETUP_SSL
    
    if [ "$SETUP_SSL" = "y" ] || [ "$SETUP_SSL" = "Y" ]; then
        echo -e "${BLUE}🔒 Настройка SSL с Let's Encrypt...${NC}"
        certbot --nginx -d $DOMAIN
        
        echo -e "${GREEN}✅ SSL сертификат установлен!${NC}"
        echo -e "${YELLOW}🔄 Не забудьте обновить SITE_URL в конфигурации Supabase (.env) на https://$DOMAIN${NC}"
        echo "   и перезапустить контейнеры: docker-compose -f $SUPABASE_DIR/docker-compose.yml restart"
    fi
    
    echo -e "${GREEN}📊 Supabase теперь доступен по адресу: http://$DOMAIN${NC}"
}

# Действие: Резервное копирование
backup_supabase() {
    echo -e "${BLUE}🚀 Создание резервной копии Supabase...${NC}"
    
    # Проверка, установлен ли Supabase
    if ! check_supabase_installed; then
        echo -e "${RED}❌ Supabase не установлен. Сначала установите Supabase.${NC}"
        return
    fi
    
    # Директория для хранения бэкапов
    BACKUP_DIR="$SUPABASE_DIR/backups"
    mkdir -p $BACKUP_DIR
    
    # Имя файла бэкапа с текущей датой
    BACKUP_FILE="$BACKUP_DIR/supabase_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Получение имени контейнера PostgreSQL
    POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        echo -e "${RED}❌ Контейнер PostgreSQL не найден. Убедитесь, что Supabase запущен.${NC}"
        return
    fi
    
    echo -e "${BLUE}📦 Создание дампа базы данных...${NC}"
    docker exec -t $POSTGRES_CONTAINER pg_dumpall -c -U postgres > $BACKUP_FILE
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Резервная копия успешно создана: $BACKUP_FILE${NC}"
        
        # Сжатие бэкапа
        gzip $BACKUP_FILE
        COMPRESSED_FILE="$BACKUP_FILE.gz"
        echo -e "${GREEN}📦 Файл бэкапа сжат: $COMPRESSED_FILE${NC}"
        
        # Очистка старых бэкапов (оставляем последние 5)
        echo -e "${BLUE}🧹 Очистка старых бэкапов...${NC}"
        ls -t $BACKUP_DIR/*.gz | tail -n +6 | xargs -r rm
        
        # Вывод размера бэкапа
        BACKUP_SIZE=$(du -h $COMPRESSED_FILE | cut -f1)
        echo -e "${GREEN}📊 Размер резервной копии: $BACKUP_SIZE${NC}"
    else
        echo -e "${RED}❌ Ошибка при создании резервной копии.${NC}"
        return
    fi
    
    echo "
${GREEN}Для восстановления из резервной копии используйте:${NC}
$ gunzip $COMPRESSED_FILE
$ cat $BACKUP_FILE | docker exec -i \$POSTGRES_CONTAINER psql -U postgres
"
}

# Действие: Восстановление из резервной копии
restore_supabase() {
    echo -e "${BLUE}🚀 Восстановление Supabase из резервной копии...${NC}"
    
    # Проверка, установлен ли Supabase
    if ! check_supabase_installed; then
        echo -e "${RED}❌ Supabase не установлен. Сначала установите Supabase.${NC}"
        return
    fi
    
    # Директория с бэкапами
    BACKUP_DIR="$SUPABASE_DIR/backups"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Директория с бэкапами не найдена: $BACKUP_DIR${NC}"
        return
    fi
    
    # Вывод списка доступных бэкапов
    echo -e "${BLUE}📋 Доступные резервные копии:${NC}"
    ls -lht $BACKUP_DIR/*.gz 2>/dev/null || echo -e "${YELLOW}Резервные копии не найдены.${NC}"
    
    # Запрос пути к файлу бэкапа
    read -p "Введите полный путь к файлу бэкапа (*.gz): " BACKUP_FILE
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ Файл не найден: $BACKUP_FILE${NC}"
        return
    fi
    
    # Получение имени контейнера PostgreSQL
    POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        echo -e "${RED}❌ Контейнер PostgreSQL не найден. Убедитесь, что Supabase запущен.${NC}"
        return
    fi
    
    # Предупреждение
    echo -e "${RED}⚠️ ВНИМАНИЕ: Восстановление удалит все текущие данные в базе данных!${NC}"
    read -p "Вы уверены, что хотите продолжить? (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Операция отменена."
        return
    fi
    
    # Распаковка бэкапа если это gzip файл
    UNCOMPRESSED_FILE="${BACKUP_FILE%.gz}"
    if [[ $BACKUP_FILE == *.gz ]]; then
        echo -e "${BLUE}📦 Распаковка бэкапа...${NC}"
        gunzip -c "$BACKUP_FILE" > "$UNCOMPRESSED_FILE"
    else
        UNCOMPRESSED_FILE="$BACKUP_FILE"
    fi
    
    echo -e "${BLUE}🔄 Восстановление базы данных... (это может занять некоторое время)${NC}"
    
    # Восстановление базы данных
    cat "$UNCOMPRESSED_FILE" | docker exec -i $POSTGRES_CONTAINER psql -U postgres
    
    # Удаление временного распакованного файла если он был создан
    if [[ $BACKUP_FILE == *.gz ]]; then
        rm -f "$UNCOMPRESSED_FILE"
    fi
    
    echo -e "${GREEN}✅ База данных успешно восстановлена из резервной копии!${NC}"
    echo -e "${YELLOW}🔄 Рекомендуется перезапустить контейнеры Supabase:${NC}"
    echo "docker-compose -f $SUPABASE_DIR/docker-compose.yml restart"
}

# Действие: Настройка автоматического бэкапа
setup_auto_backup() {
    echo -e "${BLUE}🚀 Настройка автоматического резервного копирования Supabase...${NC}"
    
    # Проверка, установлен ли Supabase
    if ! check_supabase_installed; then
        echo -e "${RED}❌ Supabase не установлен. Сначала установите Supabase.${NC}"
        return
    fi
    
    # Проверка наличия файлов скриптов
    mkdir -p $SCRIPTS_DIR
    
    # Создание скрипта для бэкапа
    BACKUP_SCRIPT="$SCRIPTS_DIR/backup_supabase.sh"
    
    cat > $BACKUP_SCRIPT << 'EOL'
#!/bin/bash
# Скрипт для создания резервной копии базы данных Supabase
set -e

# Директория для хранения бэкапов
BACKUP_DIR="/opt/supabase/backups"
mkdir -p $BACKUP_DIR

# Имя файла бэкапа с текущей датой
BACKUP_FILE="$BACKUP_DIR/supabase_backup_$(date +%Y%m%d_%H%M%S).sql"

# Получение имени контейнера PostgreSQL
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ Контейнер PostgreSQL не найден. Убедитесь, что Supabase запущен."
    exit 1
fi

echo "📦 Создание дампа базы данных..."
docker exec -t $POSTGRES_CONTAINER pg_dumpall -c -U postgres > $BACKUP_FILE

if [ $? -eq 0 ]; then
    echo "✅ Резервная копия успешно создана: $BACKUP_FILE"
    
    # Сжатие бэкапа
    gzip $BACKUP_FILE
    COMPRESSED_FILE="$BACKUP_FILE.gz"
    echo "📦 Файл бэкапа сжат: $COMPRESSED_FILE"
    
    # Очистка старых бэкапов (оставляем последние 5)
    echo "🧹 Очистка старых бэкапов..."
    ls -t $BACKUP_DIR/*.gz | tail -n +6 | xargs -r rm
    
    # Вывод размера бэкапа
    BACKUP_SIZE=$(du -h $COMPRESSED_FILE | cut -f1)
    echo "📊 Размер резервной копии: $BACKUP_SIZE"
else
    echo "❌ Ошибка при создании резервной копии."
    exit 1
fi
EOL
    
    chmod +x $BACKUP_SCRIPT
    
    # Директория для логов
    LOG_DIR="/var/log/supabase"
    mkdir -p $LOG_DIR
    
    # Выбор частоты запуска бэкапов
    echo -e "${BLUE}📅 Выберите частоту создания резервных копий:${NC}"
    echo "1) Ежедневно"
    echo "2) Еженедельно"
    echo "3) Ежемесячно"
    
    read -p "Ваш выбор (1-3): " BACKUP_FREQUENCY
    
    case $BACKUP_FREQUENCY in
        1)
            # Ежедневный бэкап в 2:00
            CRON_SCHEDULE="0 2 * * *"
            FREQUENCY_DESC="ежедневно в 2:00"
            ;;
        2)
            # Еженедельный бэкап в воскресенье в 3:00
            CRON_SCHEDULE="0 3 * * 0"
            FREQUENCY_DESC="еженедельно (воскресенье в 3:00)"
            ;;
        3)
            # Ежемесячный бэкап в первый день месяца в 4:00
            CRON_SCHEDULE="0 4 1 * *"
            FREQUENCY_DESC="ежемесячно (1-е число в 4:00)"
            ;;
        *)
            echo -e "${YELLOW}❌ Некорректный выбор. Установка ежедневного бэкапа по умолчанию.${NC}"
            CRON_SCHEDULE="0 2 * * *"
            FREQUENCY_DESC="ежедневно в 2:00"
            ;;
    esac
    
    # Настройка ротации логов (хранить логи за последние 7 дней)
    cat > /etc/logrotate.d/supabase << EOL
$LOG_DIR/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
}
EOL
    
    # Добавление задания в cron
    CRON_JOB="$CRON_SCHEDULE $BACKUP_SCRIPT > $LOG_DIR/backup_\$(date +\%Y\%m\%d).log 2>&1"
    
    # Проверка наличия такого же задания в crontab
    EXISTING_JOB=$(crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT")
    
    if [ -n "$EXISTING_JOB" ]; then
        echo -e "${YELLOW}⚠️ Уже существует задание для резервного копирования. Обновляем...${NC}"
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" ; echo "$CRON_JOB") | crontab -
    else
        (crontab -l 2>/dev/null ; echo "$CRON_JOB") | crontab -
    fi
    
    echo -e "${GREEN}✅ Настройка автоматического резервного копирования завершена!${NC}"
    echo -e "${GREEN}📅 Резервные копии будут создаваться $FREQUENCY_DESC${NC}"
    echo -e "${GREEN}📁 Бэкапы хранятся в: /opt/supabase/backups${NC}"
    echo -e "${GREEN}📝 Логи бэкапов: $LOG_DIR${NC}"
}

# Действие: Обновление Supabase
update_supabase() {
    echo -e "${BLUE}🚀 Обновление Supabase...${NC}"
    
    # Проверка, установлен ли Supabase
    if ! check_supabase_installed; then
        echo -e "${RED}❌ Supabase не установлен. Сначала установите Supabase.${NC}"
        return
    fi
    
    cd $SUPABASE_DIR
    
    # Создание резервной копии конфигурации
    cp .env .env.backup
    
    # Обновление контейнеров
    echo -e "${BLUE}🔄 Обновление контейнеров...${NC}"
    docker-compose pull
    docker-compose up -d
    
    echo -e "${GREEN}✅ Supabase успешно обновлен!${NC}"
    echo -e "${BLUE}🔍 Проверка статуса контейнеров...${NC}"
    docker-compose ps
}

# Главное меню
show_menu() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}          УСТАНОВЩИК SUPABASE              ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e ""
    echo -e "${YELLOW}Выберите действие:${NC}"
    echo -e ""
    echo -e "${GREEN}1) Установить Supabase${NC}"
    echo -e "${GREEN}2) Настроить Nginx как обратный прокси${NC}"
    echo -e "${GREEN}3) Создать резервную копию${NC}"
    echo -e "${GREEN}4) Восстановить из резервной копии${NC}"
    echo -e "${GREEN}5) Настроить автоматическое резервное копирование${NC}"
    echo -e "${GREEN}6) Обновить Supabase${NC}"
    echo -e "${GREEN}7) Выход${NC}"
    echo -e ""
    read -p "Ваш выбор (1-7): " MENU_OPTION
    
    case $MENU_OPTION in
        1) install_supabase ;;
        2) setup_nginx ;;
        3) backup_supabase ;;
        4) restore_supabase ;;
        5) setup_auto_backup ;;
        6) update_supabase ;;
        7) echo -e "${GREEN}До свидания!${NC}" ; exit 0 ;;
        *) echo -e "${RED}Некорректный выбор. Попробуйте снова.${NC}" ;;
    esac
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
    show_menu
}

# Запуск главного меню
show_menu 