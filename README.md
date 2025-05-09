# 🚀 Автоматическое развертывание Supabase

Набор скриптов для автоматического развертывания [Supabase](https://supabase.io) на VPS сервере через Docker.

## 📋 Содержимое репозитория

- `setup_supabase.sh` - основной скрипт для автоматической установки Supabase
- `setup_nginx.sh` - скрипт для настройки Nginx в качестве обратного прокси (опционально)
- `backup_supabase.sh` - скрипт для резервного копирования базы данных
- `nginx_supabase.conf` - пример конфигурации Nginx

## 🚀 Быстрый старт

1. Клонируйте этот репозиторий на свой VPS:

```bash
git clone https://github.com/ваш-аккаунт/supabase-auto-deploy.git
cd supabase-auto-deploy
```

2. Запустите скрипт установки с правами суперпользователя:

```bash
chmod +x setup_supabase.sh
sudo ./setup_supabase.sh
```

3. После завершения установки перейдите по адресу `http://ваш_IP:8000` для доступа к Supabase Studio.

## 🔧 Дополнительная настройка

### Настройка Nginx (опционально)

Если вы хотите использовать Nginx в качестве обратного прокси и/или настроить SSL:

```bash
chmod +x setup_nginx.sh
sudo ./setup_nginx.sh
```

### Создание резервной копии

Для создания резервной копии базы данных:

```bash
chmod +x backup_supabase.sh
sudo ./backup_supabase.sh
```

## 📚 Полезные команды

### Управление контейнерами

- Перезапуск Supabase:

```bash
docker-compose -f /opt/supabase/docker-compose.yml restart
```

- Остановка Supabase:

```bash
docker-compose -f /opt/supabase/docker-compose.yml down
```

- Просмотр логов:

```bash
docker-compose -f /opt/supabase/docker-compose.yml logs -f
```

### Автоматическое резервное копирование

Добавьте резервное копирование в cron для ежедневного бэкапа:

```bash
sudo crontab -e
```

Добавьте строку:

```
0 2 * * * /path/to/backup_supabase.sh > /var/log/supabase_backup.log 2>&1
```

## 📝 Учетные данные

Учетные данные сохраняются в файле `/opt/supabase/supabase_credentials.txt` после установки.

## 📜 Лицензия

MIT 