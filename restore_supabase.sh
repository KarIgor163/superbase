#!/bin/bash

# Скрипт для восстановления базы данных Supabase из резервной копии
set -e

echo "🚀 Восстановление Supabase из резервной копии..."

# Проверка наличия sudo прав
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт требует привилегий суперпользователя. Используйте sudo."
   exit 1
fi

# Директория с бэкапами
BACKUP_DIR="/opt/supabase/backups"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Директория с бэкапами не найдена: $BACKUP_DIR"
    exit 1
fi

# Вывод списка доступных бэкапов
echo "📋 Доступные резервные копии:"
ls -lht $BACKUP_DIR/*.gz 2>/dev/null || echo "Резервные копии не найдены."

# Запрос пути к файлу бэкапа
read -p "Введите полный путь к файлу бэкапа (*.gz): " BACKUP_FILE

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Файл не найден: $BACKUP_FILE"
    exit 1
fi

# Получение имени контейнера PostgreSQL
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ Контейнер PostgreSQL не найден. Убедитесь, что Supabase запущен."
    exit 1
fi

# Предупреждение
echo "⚠️ ВНИМАНИЕ: Восстановление удалит все текущие данные в базе данных!"
read -p "Вы уверены, что хотите продолжить? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Операция отменена."
    exit 0
fi

# Распаковка бэкапа если это gzip файл
UNCOMPRESSED_FILE="${BACKUP_FILE%.gz}"
if [[ $BACKUP_FILE == *.gz ]]; then
    echo "📦 Распаковка бэкапа..."
    gunzip -c "$BACKUP_FILE" > "$UNCOMPRESSED_FILE"
else
    UNCOMPRESSED_FILE="$BACKUP_FILE"
fi

echo "🔄 Восстановление базы данных... (это может занять некоторое время)"

# Восстановление базы данных
cat "$UNCOMPRESSED_FILE" | docker exec -i $POSTGRES_CONTAINER psql -U postgres

# Удаление временного распакованного файла если он был создан
if [[ $BACKUP_FILE == *.gz ]]; then
    rm -f "$UNCOMPRESSED_FILE"
fi

echo "✅ База данных успешно восстановлена из резервной копии!"
echo "🔄 Рекомендуется перезапустить контейнеры Supabase:"
echo "docker-compose -f /opt/supabase/docker-compose.yml restart" 