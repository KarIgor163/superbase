#!/bin/bash

# Скрипт для настройки автоматического резервного копирования Supabase через cron
set -e

echo "🚀 Настройка автоматического резервного копирования Supabase..."

# Проверка наличия sudo прав
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт требует привилегий суперпользователя. Используйте sudo."
   exit 1
fi

# Проверка наличия файлов скриптов
BACKUP_SCRIPT="/opt/supabase-scripts/backup_supabase.sh"
SCRIPTS_DIR="/opt/supabase-scripts"

# Создание директории для скриптов, если её нет
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "📁 Создание директории для скриптов..."
    mkdir -p $SCRIPTS_DIR
fi

# Копирование скриптов в директорию
echo "📋 Копирование скриптов..."
cp backup_supabase.sh $BACKUP_SCRIPT
chmod +x $BACKUP_SCRIPT

# Директория для логов
LOG_DIR="/var/log/supabase"
mkdir -p $LOG_DIR

# Выбор частоты запуска бэкапов
echo "📅 Выберите частоту создания резервных копий:"
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
        echo "❌ Некорректный выбор. Установка ежедневного бэкапа по умолчанию."
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
    echo "⚠️ Уже существует задание для резервного копирования. Обновляем..."
    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" ; echo "$CRON_JOB") | crontab -
else
    (crontab -l 2>/dev/null ; echo "$CRON_JOB") | crontab -
fi

echo "✅ Настройка автоматического резервного копирования завершена!"
echo "📅 Резервные копии будут создаваться $FREQUENCY_DESC"
echo "📁 Бэкапы хранятся в: /opt/supabase/backups"
echo "📝 Логи бэкапов: $LOG_DIR" 