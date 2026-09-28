#!/bin/bash
PIPE="/tmp/wallpaper_pipe"

# Запускаем сервер
~/.config/hypr/wallaper_changer/wallaper_server.sh --server > /tmp/wallpaper-server.log 2>&1 &

# Ждем пока сервер создаст pipe
sleep 2

# Тогда можно отправить команду
echo "change" > "$PIPE" 2>/dev/null
echo "Сервер запущен и обои установлены"

