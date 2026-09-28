#!/bin/bash
# wallaper_control.sh - клиент для управления сервером обоев

PIPE="/tmp/wallpaper_pipe"
COMMAND="$1"

# Проверяем наличие pipe
if [ ! -p "$PIPE" ]; then
    echo "Сервер обоев не запущен. Запускаем..." >&2
    ~/.config/hypr/wallaper_changer/wallaper_server.sh --server &>/dev/null &
    sleep 1.5
fi

# Отправляем команду в pipe
if [ -n "$COMMAND" ]; then
    if [ -p "$PIPE" ]; then
        echo "$COMMAND" > "$PIPE" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Ошибка отправки команды. Перезапускаем сервер..." >&2
            pkill -f "wallaper_server.sh" 2>/dev/null
            rm -f "$PIPE" 2>/dev/null
            ~/.config/hypr/wallaper_changer/wallaper_server.sh --server &>/dev/null &
            sleep 1.5
            if [ -p "$PIPE" ]; then
                echo "$COMMAND" > "$PIPE" 2>/dev/null
            fi
        fi
    else
        echo "Ошибка: pipe не создан" >&2
    fi
else
    echo "Использование: $0 <команда>" >&2
    echo "Команды: change, toggle_auto, change_previous, exit" >&2
fi
