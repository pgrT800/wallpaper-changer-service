#!/bin/bash

WALLPAPER_DIR="/home/admin/Pictures/wallaper"

MONITOR_COUNT=""
MONITOR_NAMES=()
WALLPAPER_DIR_ONE=""
WALLPAPER_DIR_TWO=""

PIPE="/tmp/wallpaper_pipe"

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID/bus"
LOG_FILE="/var/log/wallpaper_changer.log"
MAX_LOG_SIZE=1048576
INTERVAL=300
AUTO_CHANGE_ENABLED=true

log() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
    logger -t wallpaper-changer "$1"
}

# Твои функции (оставляем без изменений)
rename_files() {
    cd "$WALLPAPER_DIR" || return 1
    
    local files_to_rename=($(find . -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" \) \
        | grep -v -E 'photo_[0-9]+\.(jpg|png)' \
        | sed 's|^\./||'))
    
    [ ${#files_to_rename[@]} -eq 0 ] && return

    local max_num=$(find . -maxdepth 1 -type f \( -name "photo_*.jpg" -o -name "photo_*.png" \) \
        | sed -E 's/.*photo_([0-9]+)\..*/\1/' \
        | sort -n | tail -1)
    
    max_num=${max_num:-0}
    local counter=1

    for file in "${files_to_rename[@]}"; do
        local extension="${file##*.}"
        local new_name="photo_$((max_num + counter)).$extension"
        mv -n "$file" "$new_name"
        log "Переименовано: $file -> $new_name"
        ((counter++))
    done
}

get_random_files() {
    local dir="$WALLPAPER_DIR"
    
    if [ ! -d "$dir" ]; then
        log "Ошибка: директория '$dir' не существует" >&2
        return 1
    fi
    
    local files=()
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
    done < <(find "$dir" -maxdepth 1 -type f -print0)
    
    local count=${#files[@]}
    if [ "$count" -lt 2 ]; then
        log "Ошибка: в директории меньше 2 файлов (найдено: $count)" >&2
        return 1
    fi
    
    local file1 file2
    file1="${files[RANDOM % count]}"
    
    while true; do
        file2="${files[RANDOM % count]}"
        [ "$file1" != "$file2" ] && break
    done
    
    WALLPAPER_DIR_ONE="$file1"
    WALLPAPER_DIR_TWO="$file2"
}

count_mon() { 
    MONITOR_COUNT=$(xrandr --listactivemonitors 2>/dev/null | head -1 | awk '{print $NF}')
    MONITOR_NAMES=($(xrandr --listactivemonitors 2>/dev/null | sed '1d' 2>/dev/null | awk '{print $NF}'))
}

change_wallaper() {
    rename_files
    get_random_files
    
    if [ "$MONITOR_COUNT" -eq 1 ]; then
      log "One monitor wallpaper set $WALLPAPER_DIR_ONE"
      hyprctl hyprpaper wallpaper "${MONITOR_NAMES[0]}, $WALLPAPER_DIR_ONE"
    else
      log "Two monitors wallpaper set $WALLPAPER_DIR_ONE, $WALLPAPER_DIR_TWO"
      hyprctl hyprpaper wallpaper "${MONITOR_NAMES[0]}, $WALLPAPER_DIR_ONE"
      hyprctl hyprpaper wallpaper "${MONITOR_NAMES[1]}, $WALLPAPER_DIR_TWO"
    fi
    
    notify-send -t 3000 "Wallpaper" "Обои изменены" 2>/dev/null
}

process_command() {
    local cmd="$1"
    
    # Просто обрезаем перенос строки
    cmd=${cmd%$'\n'}
    cmd=${cmd%$'\r'}
    
    log "Обрабатываю команду: '$cmd'"
    
    case "$cmd" in
        change)
            log "Получена команда: change"
            count_mon
            change_wallaper
            ;;
        toggle_auto)
            log "Получена команда: toggle_auto"
            if [ "$AUTO_CHANGE_ENABLED" = true ]; then
                AUTO_CHANGE_ENABLED=false
                log "Автоматическая смена ОТКЛЮЧЕНА"
                notify-send -t 3000 "Wallpaper" "🚫 Автосмена отключена" 2>/dev/null
            else
                AUTO_CHANGE_ENABLED=true
                log "Автоматическая смена ВКЛЮЧЕНА"
                notify-send -t 3000 "Wallpaper" "✅ Автосмена включена" 2>/dev/null
                # Сбрасываем таймер при включении
                LAST_AUTO_CHANGE=$(date +%s)
            fi
            ;;
        exit|stop)
            log "Получена команда: $cmd"
            return 1
            ;;
        *)
            log "Неизвестная команда: '$cmd'"
            ;;
    esac
    
    return 0
}
main_server() {
    log "Запуск сервера смены обоев"
    
    if [ ! -p "$PIPE" ]; then
        mkfifo "$PIPE"
        log "Создан pipe: $PIPE"
    fi
    
    # Открываем pipe для чтения (дескриптор 3)
    exec 3< "$PIPE"
    
    # Первая смена при старте
    rename_files 
    count_mon
    change_wallaper
    
    trap "log 'Остановка сервера'; rm -f '$PIPE'; exec 3<&-; exit" EXIT INT TERM
    
    log "Сервер запущен. Автосмена каждые $INTERVAL секунд"
    
    # Время последней автосмены
    LAST_AUTO_CHANGE=$(date +%s)
    
    # Главный цикл
    while true; do
        CURRENT_TIME=$(date +%s)
        TIME_SINCE_LAST=$((CURRENT_TIME - LAST_AUTO_CHANGE))
        
        # Проверяем, не пришло ли время автосмены (ТОЛЬКО ЕСЛИ АВТОСМЕНА ВКЛЮЧЕНА)
        if [ "$AUTO_CHANGE_ENABLED" = true ] && [ $TIME_SINCE_LAST -ge $INTERVAL ]; then
            log "Автоматическая смена по таймеру (прошло $TIME_SINCE_LAST сек.)"
            count_mon
            change_wallaper
            LAST_AUTO_CHANGE=$CURRENT_TIME
        fi
        
        # Проверяем, есть ли команды в pipe (неблокирующее чтение)
        if read -t 0.1 -u 3 cmd 2>/dev/null; then
            if ! process_command "$cmd"; then
                break
            fi
            # Сбрасываем таймер при ручной смене обоев
            LAST_AUTO_CHANGE=$CURRENT_TIME
        fi
        
        # Короткая пауза чтобы не грузить CPU
        sleep 0.5
    done
    
    log "Сервер остановлен"
}
if [ "$1" = "--server" ]; then
    main_server
else
    echo "Используйте --server для запуска в режиме сервера"
    echo "Или используйте клиент: wallpaper-change"
fi
