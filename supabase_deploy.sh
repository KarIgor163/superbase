#!/bin/bash

# Скрипт для загрузки и установки проекта с интерактивным запросом данных
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Баннер
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       АВТОМАТИЧЕСКАЯ УСТАНОВКА ПРОЕКТА             ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Массивы для хранения учетных данных
declare -A CREDENTIALS

# Проверка зависимостей
check_dependencies() {
    echo -e "${BLUE}🔍 Проверка установленных зависимостей...${NC}"
    
    local DEPS=("git" "docker" "docker-compose" "curl" "psql" "openssl")
    local MISSING=()
    
    for dep in "${DEPS[@]}"; do
        echo -n "  - $dep: "
        if command -v $dep &> /dev/null; then
            echo -e "${GREEN}установлен${NC}"
            
            # Получение версии
            case $dep in
                "docker")
                    echo -e "    Версия: $(docker --version | cut -d' ' -f3 | tr -d ',')"
                    ;;
                "docker-compose")
                    echo -e "    Версия: $(docker-compose --version | cut -d' ' -f3 | tr -d ',')"
                    ;;
                "git")
                    echo -e "    Версия: $(git --version | cut -d' ' -f3)"
                    ;;
                "psql")
                    echo -e "    Версия: $(psql --version | cut -d' ' -f3)"
                    ;;
                "curl")
                    echo -e "    Версия: $(curl --version | head -n1 | cut -d' ' -f2)"
                    ;;
            esac
        else
            echo -e "${RED}не установлен${NC}"
            MISSING+=("$dep")
        fi
    done
    
    # Проверка прав sudo
    echo -n "  - sudo привилегии: "
    if sudo -n true 2>/dev/null; then
        echo -e "${GREEN}доступны${NC}"
    else
        echo -e "${YELLOW}требуется пароль${NC}"
    fi
    
    # Проверка статуса сервисов Docker
    echo -n "  - Docker сервис: "
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "${GREEN}запущен${NC}"
    else
        echo -e "${YELLOW}не запущен${NC}"
    fi
    
    # Если есть отсутствующие зависимости
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}⚠️ Отсутствуют следующие зависимости:${NC}"
        for dep in "${MISSING[@]}"; do
            echo "   - $dep"
        done
        
        echo -e "\n${BLUE}Установить отсутствующие зависимости? (y/n)${NC}"
        read INSTALL_DEPS
        # Удаляем возможные символы возврата каретки
        INSTALL_DEPS=$(echo "$INSTALL_DEPS" | tr -d '\r')
        
        if [ "$INSTALL_DEPS" = "y" ] || [ "$INSTALL_DEPS" = "Y" ]; then
            echo -e "${BLUE}Установка зависимостей...${NC}"
            sudo apt-get update
            for dep in "${MISSING[@]}"; do
                case $dep in
                    "docker")
                        sudo apt-get install -y docker.io
                        sudo systemctl enable docker
                        sudo systemctl start docker
                        ;;
                    "docker-compose")
                        sudo apt-get install -y docker-compose
                        ;;
                    "psql")
                        sudo apt-get install -y postgresql-client
                        ;;
                    "git")
                        sudo apt-get install -y git
                        ;;
                    "curl")
                        sudo apt-get install -y curl
                        ;;
                    "openssl")
                        sudo apt-get install -y openssl
                        ;;
                esac
            done
            echo -e "${GREEN}✅ Зависимости установлены${NC}"
        else
            echo -e "${RED}❌ Для работы скрипта требуются все зависимости. Установите их вручную и запустите скрипт снова.${NC}"
            exit 1
        fi
    fi
}

# Выбор источника проекта
select_source() {
    echo -e "\n${BLUE}📥 Выберите источник проекта:${NC}"
    echo "1) Git репозиторий"
    echo "2) Архив (curl)"
    echo "3) Локальная директория"
    
    read SOURCE_TYPE
    SOURCE_TYPE=$(echo "$SOURCE_TYPE" | tr -d '\r')
    
    case $SOURCE_TYPE in
        1)
            echo -e "\n${BLUE}Введите URL Git репозитория:${NC}"
            read REPO_URL
            REPO_URL=$(echo "$REPO_URL" | tr -d '\r')
            
            echo -e "\n${BLUE}Введите название ветки (по умолчанию: main):${NC}"
            read BRANCH_NAME
            BRANCH_NAME=$(echo "$BRANCH_NAME" | tr -d '\r')
            BRANCH_NAME=${BRANCH_NAME:-main}
            
            CREDENTIALS["project_source"]="Git: $REPO_URL (ветка: $BRANCH_NAME)"
            ;;
        2)
            echo -e "\n${BLUE}Введите URL архива:${NC}"
            read ARCHIVE_URL
            ARCHIVE_URL=$(echo "$ARCHIVE_URL" | tr -d '\r')
            CREDENTIALS["project_source"]="Archive: $ARCHIVE_URL"
            ;;
        3)
            echo -e "\n${BLUE}Введите путь к директории проекта:${NC}"
            read PROJECT_DIR
            PROJECT_DIR=$(echo "$PROJECT_DIR" | tr -d '\r')
            CREDENTIALS["project_source"]="Local directory: $PROJECT_DIR"
            ;;
        *)
            echo -e "${RED}❌ Некорректный выбор.${NC}"
            select_source
            ;;
    esac
}

# Запрос информации для установки
collect_info() {
    echo -e "\n${BLUE}📝 Ввод данных для настройки проекта${NC}"
    
    # Базовая информация о проекте
    echo -e "\n${BLUE}Название проекта:${NC}"
    read PROJECT_NAME
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr -d '\r')
    CREDENTIALS["project_name"]=$PROJECT_NAME
    
    # Директория установки
    echo -e "\n${BLUE}Директория для установки (по умолчанию: /opt/$PROJECT_NAME):${NC}"
    read INSTALL_DIR
    INSTALL_DIR=$(echo "$INSTALL_DIR" | tr -d '\r')
    INSTALL_DIR=${INSTALL_DIR:-/opt/$PROJECT_NAME}
    CREDENTIALS["install_dir"]=$INSTALL_DIR
    
    # Данные для базы данных
    echo -e "\n${BLUE}Имя пользователя базы данных (по умолчанию: postgres):${NC}"
    read DB_USER
    DB_USER=$(echo "$DB_USER" | tr -d '\r')
    DB_USER=${DB_USER:-postgres}
    CREDENTIALS["db_user"]=$DB_USER
    
    echo -e "\n${BLUE}Пароль для базы данных (по умолчанию: случайный):${NC}"
    read -s DB_PASSWORD
    DB_PASSWORD=$(echo "$DB_PASSWORD" | tr -d '\r')
    echo ""
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(openssl rand -base64 12)
    fi
    CREDENTIALS["db_password"]=$DB_PASSWORD
    
    echo -e "\n${BLUE}Имя базы данных (по умолчанию: $PROJECT_NAME):${NC}"
    read DB_NAME
    DB_NAME=$(echo "$DB_NAME" | tr -d '\r')
    DB_NAME=${DB_NAME:-$PROJECT_NAME}
    CREDENTIALS["db_name"]=$DB_NAME
    
    # Данные администратора
    echo -e "\n${BLUE}Email администратора:${NC}"
    read ADMIN_EMAIL
    ADMIN_EMAIL=$(echo "$ADMIN_EMAIL" | tr -d '\r')
    CREDENTIALS["admin_email"]=$ADMIN_EMAIL
    
    echo -e "\n${BLUE}Пароль администратора:${NC}"
    read -s ADMIN_PASSWORD
    ADMIN_PASSWORD=$(echo "$ADMIN_PASSWORD" | tr -d '\r')
    echo ""
    CREDENTIALS["admin_password"]=$ADMIN_PASSWORD
    
    # Настройки доменного имени
    echo -e "\n${BLUE}Доменное имя (опционально):${NC}"
    read DOMAIN_NAME
    DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '\r')
    CREDENTIALS["domain_name"]=${DOMAIN_NAME:-"использовать IP-адрес"}
    
    # Настройка SSL
    echo -e "\n${BLUE}Настроить SSL-сертификат? (y/n):${NC}"
    read SETUP_SSL
    SETUP_SSL=$(echo "$SETUP_SSL" | tr -d '\r')
    CREDENTIALS["setup_ssl"]=${SETUP_SSL:-"n"}
    
    # JWT Secret для API
    echo -e "\n${BLUE}JWT Secret (по умолчанию: случайный):${NC}"
    read -s JWT_SECRET
    JWT_SECRET=$(echo "$JWT_SECRET" | tr -d '\r')
    echo ""
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(openssl rand -base64 32)
    fi
    CREDENTIALS["jwt_secret"]=$JWT_SECRET
}

# Загрузка проекта
download_project() {
    echo -e "\n${BLUE}📥 Загрузка проекта...${NC}"
    
    # Создание директории установки
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown $(whoami): "$INSTALL_DIR"
    
    case $SOURCE_TYPE in
        1)
            # Git
            echo -e "${BLUE}Клонирование из Git репозитория...${NC}"
            git clone -b "$BRANCH_NAME" "$REPO_URL" "$INSTALL_DIR/temp"
            mv "$INSTALL_DIR/temp"/* "$INSTALL_DIR/"
            mv "$INSTALL_DIR/temp"/.* "$INSTALL_DIR/" 2>/dev/null || true
            rm -rf "$INSTALL_DIR/temp"
            ;;
        2)
            # Архив
            echo -e "${BLUE}Загрузка архива...${NC}"
            ARCHIVE_NAME=$(basename "$ARCHIVE_URL")
            curl -L "$ARCHIVE_URL" -o "/tmp/$ARCHIVE_NAME"
            
            # Определение типа архива и распаковка
            if [[ "$ARCHIVE_NAME" == *.zip ]]; then
                unzip "/tmp/$ARCHIVE_NAME" -d "$INSTALL_DIR/temp"
            elif [[ "$ARCHIVE_NAME" == *.tar.gz || "$ARCHIVE_NAME" == *.tgz ]]; then
                mkdir -p "$INSTALL_DIR/temp"
                tar -xzf "/tmp/$ARCHIVE_NAME" -C "$INSTALL_DIR/temp"
            elif [[ "$ARCHIVE_NAME" == *.tar ]]; then
                mkdir -p "$INSTALL_DIR/temp"
                tar -xf "/tmp/$ARCHIVE_NAME" -C "$INSTALL_DIR/temp"
            else
                echo -e "${RED}❌ Неподдерживаемый формат архива.${NC}"
                exit 1
            fi
            
            # Перемещение файлов и удаление временной директории
            EXTRACTED_DIR=$(ls -d "$INSTALL_DIR/temp"/*/ 2>/dev/null | head -n1)
            if [ -n "$EXTRACTED_DIR" ]; then
                mv "$EXTRACTED_DIR"/* "$INSTALL_DIR/"
                mv "$EXTRACTED_DIR"/.* "$INSTALL_DIR/" 2>/dev/null || true
            else
                mv "$INSTALL_DIR/temp"/* "$INSTALL_DIR/"
                mv "$INSTALL_DIR/temp"/.* "$INSTALL_DIR/" 2>/dev/null || true
            fi
            rm -rf "$INSTALL_DIR/temp"
            rm "/tmp/$ARCHIVE_NAME"
            ;;
        3)
            # Локальная директория
            echo -e "${BLUE}Копирование из локальной директории...${NC}"
            cp -r "$PROJECT_DIR"/* "$INSTALL_DIR/"
            cp -r "$PROJECT_DIR"/.[^.]* "$INSTALL_DIR/" 2>/dev/null || true
            ;;
    esac
    
    echo -e "${GREEN}✅ Проект загружен в $INSTALL_DIR${NC}"
}

# Настройка конфигурации
configure_project() {
    echo -e "\n${BLUE}⚙️ Настройка конфигурации проекта...${NC}"
    
    # Проверка наличия файла .env или .env.example
    ENV_FILE="$INSTALL_DIR/.env"
    ENV_EXAMPLE="$INSTALL_DIR/.env.example"
    
    if [ ! -f "$ENV_FILE" ] && [ -f "$ENV_EXAMPLE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
    elif [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
    fi
    
    # Настройка переменных окружения
    # База данных
    sed -i "s/DB_USER=.*/DB_USER=$DB_USER/" "$ENV_FILE" 2>/dev/null || \
        echo "DB_USER=$DB_USER" >> "$ENV_FILE"
    
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" "$ENV_FILE" 2>/dev/null || \
        echo "DB_PASSWORD=$DB_PASSWORD" >> "$ENV_FILE"
    
    sed -i "s/DB_NAME=.*/DB_NAME=$DB_NAME/" "$ENV_FILE" 2>/dev/null || \
        echo "DB_NAME=$DB_NAME" >> "$ENV_FILE"
    
    # JWT
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" "$ENV_FILE" 2>/dev/null || \
        echo "JWT_SECRET=$JWT_SECRET" >> "$ENV_FILE"
    
    # Домен
    if [ -n "$DOMAIN_NAME" ]; then
        sed -i "s/APP_URL=.*/APP_URL=https:\/\/$DOMAIN_NAME/" "$ENV_FILE" 2>/dev/null || \
            echo "APP_URL=https://$DOMAIN_NAME" >> "$ENV_FILE"
    else
        # Получение IP-адреса сервера
        SERVER_IP=$(curl -s ifconfig.me)
        sed -i "s/APP_URL=.*/APP_URL=http:\/\/$SERVER_IP/" "$ENV_FILE" 2>/dev/null || \
            echo "APP_URL=http://$SERVER_IP" >> "$ENV_FILE"
    fi
    
    # Admin
    sed -i "s/ADMIN_EMAIL=.*/ADMIN_EMAIL=$ADMIN_EMAIL/" "$ENV_FILE" 2>/dev/null || \
        echo "ADMIN_EMAIL=$ADMIN_EMAIL" >> "$ENV_FILE"
    
    sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$ADMIN_PASSWORD/" "$ENV_FILE" 2>/dev/null || \
        echo "ADMIN_PASSWORD=$ADMIN_PASSWORD" >> "$ENV_FILE"
    
    echo -e "${GREEN}✅ Конфигурация настроена${NC}"
}

# Запуск проекта
run_project() {
    echo -e "\n${BLUE}🚀 Запуск проекта...${NC}"
    
    cd "$INSTALL_DIR"
    
    # Проверка наличия docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        echo -e "${BLUE}Запуск Docker контейнеров...${NC}"
        sudo docker-compose pull
        sudo docker-compose up -d
    else
        echo -e "${YELLOW}⚠️ docker-compose.yml не найден. Проверьте директорию проекта.${NC}"
        
        # Проверка наличия скрипта установки
        if [ -f "setup.sh" ]; then
            echo -e "${BLUE}Найден скрипт setup.sh. Запуск...${NC}"
            sudo chmod +x setup.sh
            sudo ./setup.sh
        elif [ -f "install.sh" ]; then
            echo -e "${BLUE}Найден скрипт install.sh. Запуск...${NC}"
            sudo chmod +x install.sh
            sudo ./install.sh
        else
            echo -e "${RED}❌ Не найдены скрипты установки. Требуется ручная настройка.${NC}"
        fi
    fi
    
    # Сохранение данных в файл
    echo -e "\n${BLUE}💾 Сохранение учетных данных...${NC}"
    CREDENTIALS_FILE="$INSTALL_DIR/project_credentials.txt"
    
    echo "================================================" > "$CREDENTIALS_FILE"
    echo "            УЧЕТНЫЕ ДАННЫЕ ПРОЕКТА              " >> "$CREDENTIALS_FILE"
    echo "================================================" >> "$CREDENTIALS_FILE"
    echo "Дата установки: $(date)" >> "$CREDENTIALS_FILE"
    echo "" >> "$CREDENTIALS_FILE"
    
    for key in "${!CREDENTIALS[@]}"; do
        echo "$key: ${CREDENTIALS[$key]}" >> "$CREDENTIALS_FILE"
    done
    
    chmod 600 "$CREDENTIALS_FILE"
    echo -e "${GREEN}✅ Учетные данные сохранены в $CREDENTIALS_FILE${NC}"
}

# Настройка Nginx (опционально)
setup_nginx() {
    if [ -n "$DOMAIN_NAME" ]; then
        echo -e "\n${BLUE}🌐 Настройка Nginx для $DOMAIN_NAME...${NC}"
        
        # Установка Nginx если не установлен
        if ! command -v nginx &> /dev/null; then
            echo -e "${BLUE}Установка Nginx...${NC}"
            sudo apt-get update
            sudo apt-get install -y nginx
        fi
        
        # Создание конфига Nginx
        NGINX_CONF="/etc/nginx/sites-available/$DOMAIN_NAME"
        
        sudo bash -c "cat > $NGINX_CONF << EOL
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
EOL"
        
        # Активация сайта и перезапуск Nginx
        sudo ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/"
        sudo nginx -t && sudo systemctl restart nginx
        
        # Настройка SSL если требуется
        if [[ "$SETUP_SSL" == "y" || "$SETUP_SSL" == "Y" ]]; then
            echo -e "${BLUE}🔒 Настройка SSL с Let's Encrypt...${NC}"
            
            # Установка Certbot если не установлен
            if ! command -v certbot &> /dev/null; then
                sudo apt-get update
                sudo apt-get install -y certbot python3-certbot-nginx
            fi
            
            # Получение сертификата
            sudo certbot --nginx -d "$DOMAIN_NAME"
        fi
        
        echo -e "${GREEN}✅ Nginx настроен для $DOMAIN_NAME${NC}"
    fi
}

# Вывод результатов
show_results() {
    echo -e "\n${BLUE}====================================================${NC}"
    echo -e "${GREEN}✅ УСТАНОВКА ЗАВЕРШЕНА${NC}"
    echo -e "${BLUE}====================================================${NC}"
    
    echo -e "\n${YELLOW}📝 СОХРАНЕННЫЕ УЧЕТНЫЕ ДАННЫЕ:${NC}"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    
    for key in "${!CREDENTIALS[@]}"; do
        # Маскировка пароля при выводе
        if [[ "$key" == *"password"* || "$key" == *"secret"* ]]; then
            # Показываем только первые и последние 2 символа, остальное скрыто
            value="${CREDENTIALS[$key]}"
            length=${#value}
            
            if [ "$length" -gt 5 ]; then
                masked_value="${value:0:2}$(printf '%*s' $((length-4)) | tr ' ' '*')${value: -2}"
            else
                masked_value="*****"
            fi
            
            echo -e "${GREEN}$key:${NC} $masked_value"
        else
            echo -e "${GREEN}$key:${NC} ${CREDENTIALS[$key]}"
        fi
    done
    
    echo -e "${BLUE}---------------------------------------------------${NC}"
    
    # Вывод информации о доступе
    echo -e "\n${BLUE}📊 ДОСТУП К ПРОЕКТУ:${NC}"
    
    if [ -n "$DOMAIN_NAME" ]; then
        if [[ "$SETUP_SSL" == "y" || "$SETUP_SSL" == "Y" ]]; then
            echo -e "${GREEN}URL:${NC} https://$DOMAIN_NAME"
        else
            echo -e "${GREEN}URL:${NC} http://$DOMAIN_NAME"
        fi
    else
        SERVER_IP=$(curl -s ifconfig.me)
        echo -e "${GREEN}URL:${NC} http://$SERVER_IP:8000"
    fi
    
    echo -e "${GREEN}Директория проекта:${NC} $INSTALL_DIR"
    echo -e "${GREEN}Файл с учетными данными:${NC} $CREDENTIALS_FILE"
    
    echo -e "\n${BLUE}====================================================${NC}"
    echo -e "${BLUE}            БЛАГОДАРИМ ЗА УСТАНОВКУ!               ${NC}"
    echo -e "${BLUE}====================================================${NC}"
}

# Основная функция
main() {
    # Проверка зависимостей
    check_dependencies
    
    # Выбор источника
    select_source
    
    # Сбор данных
    collect_info
    
    # Загрузка проекта
    download_project
    
    # Настройка
    configure_project
    
    # Запуск
    run_project
    
    # Настройка Nginx
    setup_nginx
    
    # Вывод результатов
    show_results
}

# Запуск скрипта
main 
