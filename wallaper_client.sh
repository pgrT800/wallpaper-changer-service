#!/bin/bash
# Минимальный клиент для смены обоев через pipe
# Всего 7 строк!

PIPE="/tmp/wallpaper_pipe"

COMMAND="${1:-change}"
# Если pipe нет - создаём сервер
[ -p "$PIPE" ] || {
    ~/.config/hypr/scripts/wallpaper-server.sh &>/dev/null &
    sleep 0.5
}

# Отправляем команду "change" (смена обоев)
echo "$COMMAND" > "$PIPE" 2>/dev/null

# Если ошибка - пытаемся восстановить
if [ $? -ne 0 ]; then
    # Чистим и запускаем заново
    pkill -f "wallpaper-server.sh" 2>/dev/null
    rm -f "$PIPE" 2>/dev/null
    ~/.config/hypr/scripts/wallpaper-server.sh &>/dev/null &
    sleep 1
    echo "change" > "$PIPE" 2>/dev/null
fi

