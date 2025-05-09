#!/bin/bash

# Скрипт для автоматического развертывания Supabase на VPS
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Файл для хранения учетных данных
CREDENTIALS_FILE="/root/.supabase_credentials"

# Баннер
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    АВТОМАТИЧЕСКОЕ РАЗВЕРТЫВАНИЕ SUPABASE НА VPS    ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Функция для логирования ошибок
log_error() {
    local ERROR_MSG="$1"
    local ERROR_FILE="baza_script.txt"
    local DATE=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo -e "\n[${DATE}] [ERROR] - ${ERROR_MSG}" >> "$ERROR_FILE"
    echo -e "${RED}❌ Ошибка: ${ERROR_MSG}${NC}"
}

# Функция для безопасного ввода
safe_read() {
    local VAR_NAME=$1
    local DEFAULT_VALUE=$2
    local PROMPT=$3
    local HIDE_INPUT=$4
    
    # Если есть значение по умолчанию, показать его в скобках
    if [ -n "$DEFAULT_VALUE" ]; then
        echo -e "${BLUE}${PROMPT} (${DEFAULT_VALUE}):${NC}"
    else
        echo -e "${BLUE}${PROMPT}:${NC}"
    fi
    
    # Режим скрытого ввода для паролей
    if [ "$HIDE_INPUT" = "true" ]; then
        read -s USER_INPUT
        echo "" # Новая строка после скрытого ввода
    else
        read USER_INPUT
    fi
    
    # Очистка ввода от символов возврата каретки
    USER_INPUT=$(echo "$USER_INPUT" | tr -d '\r')
    
    # Если ввод пустой - использовать значение по умолчанию
    if [ -z "$USER_INPUT" ] && [ -n "$DEFAULT_VALUE" ]; then
        USER_INPUT="$DEFAULT_VALUE"
    fi
    
    # Сохранение в указанную переменную через eval
    eval "$VAR_NAME=\"$USER_INPUT\""
}

# Функция для безопасного выбора из опций
safe_select() {
    local VAR_NAME=$1
    local PROMPT=$2
    shift 2
    local OPTIONS=("$@")
    
    echo -e "${BLUE}${PROMPT}${NC}"
    
    # Вывод опций с номерами
    for ((i=0; i<${#OPTIONS[@]}; i++)); do
        echo "$(($i+1))) ${OPTIONS[$i]}"
    done
    
    # Чтение ввода и очистка символов возврата каретки
    read USER_INPUT
    USER_INPUT=$(echo "$USER_INPUT" | tr -d '\r')
    
    # Проверка ввода на корректность
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]] && [ "$USER_INPUT" -ge 1 ] && [ "$USER_INPUT" -le ${#OPTIONS[@]} ]; then
        # Ввод корректный - сохраняем выбранный индекс (с учетом что массивы с 0, а опции с 1)
        eval "$VAR_NAME=$((USER_INPUT-1))"
        return 0
    else
        echo -e "${RED}Некорректный выбор. Попробуйте снова.${NC}"
        # Рекурсивный вызов для повторного выбора
        safe_select "$VAR_NAME" "$PROMPT" "${OPTIONS[@]}"
    fi
}

# Функция для безопасного выбора да/нет
safe_yes_no() {
    local VAR_NAME=$1
    local PROMPT=$2
    local DEFAULT=$3
    
    local DEFAULT_DISPLAY=""
    if [ "$DEFAULT" = "y" ]; then
        DEFAULT_DISPLAY=" [Y/n]"
    elif [ "$DEFAULT" = "n" ]; then
        DEFAULT_DISPLAY=" [y/N]"
    else
        DEFAULT_DISPLAY=" [y/n]"
    fi
    
    echo -e "${BLUE}${PROMPT}${DEFAULT_DISPLAY}:${NC}"
    read USER_INPUT
    USER_INPUT=$(echo "$USER_INPUT" | tr -d '\r')
    
    # Если ввод пустой и есть значение по умолчанию
    if [ -z "$USER_INPUT" ] && [ -n "$DEFAULT" ]; then
        USER_INPUT="$DEFAULT"
    fi
    
    case "$USER_INPUT" in
        y|Y|yes|Yes|YES)
            eval "$VAR_NAME=true"
            ;;
        n|N|no|No|NO)
            eval "$VAR_NAME=false"
            ;;
        *)
            echo -e "${RED}Некорректный выбор. Введите 'y' или 'n'.${NC}"
            safe_yes_no "$VAR_NAME" "$PROMPT" "$DEFAULT"
            ;;
    esac
}

# Массивы для хранения учетных данных
declare -A CREDENTIALS

# Проверка зависимостей
check_dependencies() {
    echo -e "${BLUE}🔍 Проверка установленных зависимостей...${NC}"
    
    local DEPS=("git" "docker" "docker-compose" "curl" "openssl")
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
        
        # Использование безопасной функции выбора
        safe_yes_no "INSTALL_DEPS" "Установить отсутствующие зависимости?" "y"
        
        if [ "$INSTALL_DEPS" = "true" ]; then
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
            log_error "Установка прервана из-за отсутствия необходимых зависимостей"
            exit 1
        fi
    fi
}

# Выбор источника проекта
select_source() {
    echo -e "\n${BLUE}📥 Выбор источника Supabase:${NC}"
    
    local OPTIONS=("Официальный Git репозиторий" "Локальная директория" "Собственный Git репозиторий")
    safe_select "SOURCE_TYPE" "Выберите источник Supabase:" "${OPTIONS[@]}"
    
    case $SOURCE_TYPE in
        0) # Официальный Git репозиторий
            REPO_URL="https://github.com/supabase/supabase.git"
            safe_read "BRANCH_NAME" "master" "Введите название ветки"
            CREDENTIALS["project_source"]="Git: $REPO_URL (ветка: $BRANCH_NAME)"
            ;;
        1) # Локальная директория
            safe_read "PROJECT_DIR" "" "Введите путь к директории проекта"
            CREDENTIALS["project_source"]="Local directory: $PROJECT_DIR"
            ;;
        2) # Собственный Git репозиторий
            safe_read "REPO_URL" "" "Введите URL своего Git репозитория"
            safe_read "BRANCH_NAME" "main" "Введите название ветки"
            CREDENTIALS["project_source"]="Custom Git: $REPO_URL (ветка: $BRANCH_NAME)"
            ;;
    esac
}

# Запрос информации для установки Supabase
collect_info() {
    echo -e "\n${BLUE}📝 Ввод данных для настройки Supabase${NC}"
    
    # Базовая информация о проекте
    safe_read "PROJECT_NAME" "supabase" "Название проекта"
    CREDENTIALS["project_name"]=$PROJECT_NAME
    
    # Директория установки
    safe_read "INSTALL_DIR" "/opt/$PROJECT_NAME" "Директория для установки"
    CREDENTIALS["install_dir"]=$INSTALL_DIR
    
    # Данные для базы данных
    safe_read "DB_USER" "postgres" "Имя пользователя базы данных"
    CREDENTIALS["db_user"]=$DB_USER
    
    safe_read "DB_PASSWORD" "" "Пароль для базы данных (оставьте пустым для генерации случайного)" "true"
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(openssl rand -base64 12)
        echo -e "${YELLOW}Сгенерирован случайный пароль: $DB_PASSWORD${NC}"
    fi
    CREDENTIALS["db_password"]=$DB_PASSWORD
    
    safe_read "DB_PORT" "5432" "Порт PostgreSQL"
    CREDENTIALS["db_port"]=$DB_PORT
    
    # Данные для админа
    safe_read "ADMIN_EMAIL" "admin@example.com" "Email администратора"
    CREDENTIALS["admin_email"]=$ADMIN_EMAIL
    
    safe_read "ADMIN_PASSWORD" "" "Пароль администратора (оставьте пустым для генерации случайного)" "true"
    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(openssl rand -base64 12)
        echo -e "${YELLOW}Сгенерирован случайный пароль: $ADMIN_PASSWORD${NC}"
    fi
    CREDENTIALS["admin_password"]=$ADMIN_PASSWORD
    
    # Настройки доменного имени
    safe_read "DOMAIN_NAME" "" "Доменное имя (опционально, оставьте пустым для использования IP)"
    CREDENTIALS["domain_name"]=${DOMAIN_NAME:-"использовать IP-адрес"}
    
    # Настройка SSL
    if [ -n "$DOMAIN_NAME" ]; then
        safe_yes_no "SETUP_SSL" "Настроить SSL-сертификат через Let's Encrypt?" "y"
        CREDENTIALS["setup_ssl"]=$SETUP_SSL
    else
        SETUP_SSL=false
        CREDENTIALS["setup_ssl"]=$SETUP_SSL
    fi
    
    # Генерация JWT секрета
    JWT_SECRET=$(openssl rand -base64 32)
    CREDENTIALS["jwt_secret"]=$JWT_SECRET
    
    # Порты для сервисов
    safe_read "STUDIO_PORT" "3000" "Порт для Supabase Studio"
    CREDENTIALS["studio_port"]=$STUDIO_PORT
    
    safe_read "REST_PORT" "8000" "Порт для REST API"
    CREDENTIALS["rest_port"]=$REST_PORT
}

# Загрузка и настройка Supabase
download_supabase() {
    echo -e "\n${BLUE}📥 Загрузка Supabase...${NC}"
    
    # Создание директории установки
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown $(whoami): "$INSTALL_DIR"
    
    case $SOURCE_TYPE in
        0|2) # Git репозиторий (официальный или собственный)
            echo -e "${BLUE}Клонирование из Git репозитория...${NC}"
            git clone -b "$BRANCH_NAME" "$REPO_URL" "$INSTALL_DIR/temp" || {
                log_error "Не удалось клонировать репозиторий $REPO_URL ветка $BRANCH_NAME"
                exit 1
            }
            
            # Перемещение файлов из директории examples/docker
            if [ -d "$INSTALL_DIR/temp/examples/docker" ]; then
                cp -r "$INSTALL_DIR/temp/examples/docker"/* "$INSTALL_DIR/"
                echo -e "${GREEN}Скопированы файлы из examples/docker${NC}"
            else
                # Если стандартная структура не найдена, просто копируем все содержимое
                mv "$INSTALL_DIR/temp"/* "$INSTALL_DIR/" 2>/dev/null || true
                mv "$INSTALL_DIR/temp"/.* "$INSTALL_DIR/" 2>/dev/null || true
                echo -e "${YELLOW}Структура репозитория нестандартная, скопированы все файлы${NC}"
            fi
            
            rm -rf "$INSTALL_DIR/temp"
            ;;
        1) # Локальная директория
            echo -e "${BLUE}Копирование из локальной директории...${NC}"
            cp -r "$PROJECT_DIR"/* "$INSTALL_DIR/" || {
                log_error "Не удалось скопировать файлы из $PROJECT_DIR"
                exit 1
            }
            cp -r "$PROJECT_DIR"/.[^.]* "$INSTALL_DIR/" 2>/dev/null || true
            ;;
    esac
    
    echo -e "${GREEN}✅ Supabase загружен в $INSTALL_DIR${NC}"
}

# Настройка конфигурации Supabase
configure_supabase() {
    echo -e "\n${BLUE}⚙️ Настройка конфигурации Supabase...${NC}"
    
    cd "$INSTALL_DIR"
    
    # Проверка наличия docker-compose.yml
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Файл docker-compose.yml не найден в директории $INSTALL_DIR"
        echo -e "${RED}Файл docker-compose.yml не найден. Убедитесь, что вы выбрали правильный источник.${NC}"
        exit 1
    fi
    
    # Создание .env файла
    echo -e "${BLUE}Создание .env файла...${NC}"
    cat > .env << EOL
# Supabase configuration
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=postgres
POSTGRES_USER=${DB_USER}
POSTGRES_PORT=${DB_PORT}

# JWT
SUPABASE_JWT_SECRET=${JWT_SECRET}

# API and Studio ports
STUDIO_PORT=${STUDIO_PORT}
API_PORT=${REST_PORT}

# Email for Let's Encrypt
ADMIN_EMAIL=${ADMIN_EMAIL}

# Domain settings
EOL

    # Добавление настроек домена если указан
    if [ -n "$DOMAIN_NAME" ]; then
        echo "DOMAIN=${DOMAIN_NAME}" >> .env
    else
        # Получение IP-адреса сервера
        SERVER_IP=$(curl -s ifconfig.me)
        echo "# IP address instead of domain" >> .env
        echo "SERVER_IP=${SERVER_IP}" >> .env
    fi
    
    # Создание или модификация Kong конфигурации если необходимо
    if [ -f "volumes/api/kong.yml" ]; then
        # Настройка JWT секрета
        sed -i "s/jwt_secret:.*/jwt_secret: ${JWT_SECRET}/" volumes/api/kong.yml
    fi
    
    # Настройка SSL если требуется
    if [ "$SETUP_SSL" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
        echo -e "${BLUE}Настройка SSL для домена $DOMAIN_NAME...${NC}"
        # Проверка наличия директории для Certbot
        mkdir -p "volumes/certbot/conf"
        
        # Модификация docker-compose для поддержки SSL
        if ! grep -q "certbot" docker-compose.yml; then
            echo -e "${BLUE}Добавление Certbot в docker-compose.yml...${NC}"
            # Здесь можно добавить сервис Certbot в docker-compose.yml
            # или создать отдельный docker-compose.ssl.yml
        fi
    fi
    
    echo -e "${GREEN}✅ Конфигурация Supabase настроена${NC}"
}

# Запуск Supabase
start_supabase() {
    echo -e "\n${BLUE}🚀 Запуск Supabase...${NC}"
    
    cd "$INSTALL_DIR"
    
    # Проверка наличия docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        echo -e "${BLUE}Запуск Docker контейнеров...${NC}"
        sudo docker-compose pull
        sudo docker-compose up -d || {
            log_error "Не удалось запустить контейнеры Docker"
            echo -e "${RED}❌ Ошибка при запуске контейнеров. Проверьте логи Docker для подробностей.${NC}"
            echo -e "${YELLOW}Вы можете проверить логи с помощью команды: sudo docker-compose logs${NC}"
            exit 1
        }
        
        echo -e "${GREEN}✅ Supabase успешно запущен!${NC}"
        
        # Вывод информации о доступе
        echo -e "\n${BLUE}📋 Информация о доступе:${NC}"
        echo -e "${GREEN}Studio URL:${NC} http://localhost:${STUDIO_PORT}"
        echo -e "${GREEN}REST API:${NC} http://localhost:${REST_PORT}/rest/v1/"
        
        if [ -n "$DOMAIN_NAME" ]; then
            echo -e "${GREEN}Публичный URL:${NC} http://${DOMAIN_NAME}"
            if [ "$SETUP_SSL" = "true" ]; then
                echo -e "${GREEN}Защищенный URL:${NC} https://${DOMAIN_NAME}"
            fi
        else
            SERVER_IP=$(curl -s ifconfig.me)
            echo -e "${GREEN}Публичный URL:${NC} http://${SERVER_IP}"
        fi
    else
        log_error "Файл docker-compose.yml не найден"
        echo -e "${RED}❌ docker-compose.yml не найден. Проверьте директорию проекта.${NC}"
        exit 1
    fi
}

# Сохранение учетных данных
save_credentials() {
    echo -e "\n${BLUE}🔐 Сохранение учетных данных...${NC}"
    
    # Создание файла с учетными данными
    cat > "$INSTALL_DIR/credentials.txt" << EOL
# Учетные данные Supabase
# Дата установки: $(date "+%Y-%m-%d %H:%M:%S")
#
# ВНИМАНИЕ: Этот файл содержит конфиденциальную информацию!
# Храните его в безопасном месте и ограничьте доступ.

[Проект]
Название проекта: ${CREDENTIALS["project_name"]}
Директория установки: ${CREDENTIALS["install_dir"]}
Источник: ${CREDENTIALS["project_source"]}

[База данных]
Пользователь: ${CREDENTIALS["db_user"]}
Пароль: ${CREDENTIALS["db_password"]}
Порт: ${CREDENTIALS["db_port"]}

[Администратор]
Email: ${CREDENTIALS["admin_email"]}
Пароль: ${CREDENTIALS["admin_password"]}

[Доступ]
Studio URL: http://localhost:${CREDENTIALS["studio_port"]}
REST API: http://localhost:${CREDENTIALS["rest_port"]}/rest/v1/
EOL

    # Добавление информации о домене если указан
    if [ -n "$DOMAIN_NAME" ]; then
        echo "Домен: ${CREDENTIALS["domain_name"]}" >> "$INSTALL_DIR/credentials.txt"
        if [ "$SETUP_SSL" = "true" ]; then
            echo "SSL: Настроен через Let's Encrypt" >> "$INSTALL_DIR/credentials.txt"
        else
            echo "SSL: Не настроен" >> "$INSTALL_DIR/credentials.txt"
        fi
    else
        SERVER_IP=$(curl -s ifconfig.me)
        echo "IP адрес: ${SERVER_IP}" >> "$INSTALL_DIR/credentials.txt"
    fi
    
    # Защита файла с учетными данными
    chmod 600 "$INSTALL_DIR/credentials.txt"
    
    echo -e "${GREEN}✅ Учетные данные сохранены в $INSTALL_DIR/credentials.txt${NC}"
    echo -e "${YELLOW}⚠️ Рекомендуется сделать резервную копию этого файла и ограничить к нему доступ!${NC}"
}

# Настройка Nginx (если выбрана)
setup_nginx() {
    echo -e "\n${BLUE}🔄 Настройка Nginx...${NC}"
    
    safe_yes_no "SETUP_NGINX" "Настроить Nginx как прокси для Supabase?" "y"
    
    if [ "$SETUP_NGINX" = "true" ]; then
        # Установка Nginx если не установлен
        if ! command -v nginx &> /dev/null; then
            echo -e "${BLUE}Установка Nginx...${NC}"
            sudo apt-get update
            sudo apt-get install -y nginx
        fi
        
        # Создание конфигурации Nginx
        echo -e "${BLUE}Создание конфигурации Nginx...${NC}"
        
        # Определение имени хоста
        local SERVER_NAME="${DOMAIN_NAME:-$(curl -s ifconfig.me)}"
        
        # Создание конфигурационного файла
        sudo tee /etc/nginx/sites-available/supabase.conf > /dev/null << EOL
server {
    listen 80;
    server_name ${SERVER_NAME};

    location / {
        proxy_pass http://localhost:${STUDIO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /rest/ {
        proxy_pass http://localhost:${REST_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
        
        # Активация конфигурации
        sudo ln -sf /etc/nginx/sites-available/supabase.conf /etc/nginx/sites-enabled/
        
        # Проверка конфигурации и перезапуск Nginx
        echo -e "${BLUE}Проверка конфигурации Nginx...${NC}"
        sudo nginx -t
        
        if [ $? -eq 0 ]; then
            echo -e "${BLUE}Перезапуск Nginx...${NC}"
            sudo systemctl restart nginx
            echo -e "${GREEN}✅ Nginx настроен и запущен${NC}"
        else
            log_error "Ошибка в конфигурации Nginx"
            echo -e "${RED}❌ Ошибка в конфигурации Nginx. Проверьте синтаксис.${NC}"
        fi
    else
        echo -e "${YELLOW}Настройка Nginx пропущена.${NC}"
    fi
}

# Установка SSL с Let's Encrypt (если выбрана)
setup_ssl() {
    if [ "$SETUP_SSL" = "true" ] && [ -n "$DOMAIN_NAME" ]; then
        echo -e "\n${BLUE}🔒 Настройка SSL с Let's Encrypt...${NC}"
        
        # Установка certbot если не установлен
        if ! command -v certbot &> /dev/null; then
            echo -e "${BLUE}Установка Certbot...${NC}"
            sudo apt-get update
            sudo apt-get install -y certbot python3-certbot-nginx
        fi
        
        # Получение сертификата
        echo -e "${BLUE}Получение SSL сертификата для домена ${DOMAIN_NAME}...${NC}"
        sudo certbot --nginx -d ${DOMAIN_NAME} --non-interactive --agree-tos -m ${ADMIN_EMAIL}
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ SSL сертификат успешно получен и настроен${NC}"
        else
            log_error "Не удалось получить SSL сертификат для домена ${DOMAIN_NAME}"
            echo -e "${RED}❌ Ошибка при получении SSL сертификата. Проверьте доступность домена и DNS настройки.${NC}"
        fi
    fi
}

# Основная функция
main() {
    # Проверка зависимостей
    check_dependencies
    
    # Выбор источника
    select_source
    
    # Сбор информации
    collect_info
    
    # Загрузка Supabase
    download_supabase
    
    # Настройка
    configure_supabase
    
    # Запуск
    start_supabase
    
    # Настройка Nginx
    setup_nginx
    
    # Настройка SSL
    setup_ssl
    
    # Сохранение учетных данных
    save_credentials
    
    echo -e "\n${GREEN}✅ Установка Supabase завершена успешно!${NC}"
    echo -e "${BLUE}Учетные данные сохранены в: ${INSTALL_DIR}/credentials.txt${NC}"
}

# Запуск основной функции
main 
