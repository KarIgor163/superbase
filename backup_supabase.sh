#!/bin/bash

# Скрипт для создания резервной копии базы данных Supabase
set -e

echo "🚀 Создание резервной копии Supabase..."

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

echo "
Для восстановления из резервной копии используйте:
$ gunzip $COMPRESSED_FILE
$ cat $BACKUP_FILE | docker exec -i \$POSTGRES_CONTAINER psql -U postgres
" 