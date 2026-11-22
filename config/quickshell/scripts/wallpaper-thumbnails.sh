#!/bin/sh
# wallpaper-thumbnails.sh — список бібліотеки шпалер і кешовані 16:9 мініатюри.
#
# Використання: wallpaper-thumbnails.sh <wallpaper-dir> <cache-dir>
#
# Друкує по одному запису на рядок, розділяючи поля табуляцією:
#   total<TAB><кількість>
#   <шлях-до-шпалер><TAB><шлях-до-мініатюри>
#
# Готові мініатюри друкуються першими, тому панель показує те, що вже є в
# кеші, поки решта ще генерується. Ключ кешу містить mtime джерела: змінений
# файл отримує нову мініатюру, незмінені ніколи не перекодовуються.
#
# Quickshell не забирає своїх дітей після завершення, тому воркер спершу
# зупиняє ідентичний воркер, що лишився від попередньої оболонки (повний
# збіг argv, як у cliphist-watch.sh). Мініатюра пишеться в тимчасовий файл і
# перейменовується, тож скасування не лишає обрізаний JPEG.

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <wallpaper-dir> <cache-dir>" >&2
    exit 2
fi

src=$1
cache=$2

mkdir -p "$cache"

# Зупиняємо воркер попередньої оболонки. Порівнюємо повний argv, щоб не
# зачепити разовий ffmpeg чи редактор, який просто згадує цей скрипт.
for cmdline in /proc/[0-9]*/cmdline; do
    pid=${cmdline#/proc/}
    pid=${pid%/cmdline}
    [ "$pid" = "$$" ] && continue
    args=$(tr '\0' '\n' 2>/dev/null < "$cmdline") || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    [ "$#" -eq 4 ] || continue
    [ "${1##*/}" = "sh" ] || continue
    [ "${2##*/}" = "wallpaper-thumbnails.sh" ] || continue
    [ "$3" = "$src" ] || continue
    [ "$4" = "$cache" ] || continue
    kill "$pid" 2>/dev/null || true
done

list_file="$cache/.list.$$"
plan_file="$cache/.plan.$$"
thumb_tmp=""
ffmpeg_pid=""

cleanup() {
    rm -f "$list_file" "$plan_file"
    if [ -n "$thumb_tmp" ]; then
        rm -f "$thumb_tmp"
    fi
}

cancel() {
    if [ -n "$ffmpeg_pid" ]; then
        kill "$ffmpeg_pid" 2>/dev/null || true
        wait "$ffmpeg_pid" 2>/dev/null || true
    fi
    cleanup
    exit 143
}

trap cleanup EXIT
trap cancel TERM INT HUP

# Ті самі розширення, що й у random-wallpaper.sh, щоб список і випадковий
# вибір бачили однаковий набір файлів.
find "$src" -maxdepth 1 -type f \
    \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' \) \
    -print 2>/dev/null | LC_ALL=C sort > "$list_file" || true

total=$(wc -l < "$list_file" | tr -d ' ')
printf 'total\t%s\n' "$total"

while IFS= read -r path; do
    [ -n "$path" ] || continue
    mtime=$(stat -c '%Y' -- "$path" 2>/dev/null) || mtime=0
    digest=$(printf '%s\n%s\n' "$path" "$mtime" | sha1sum)
    digest=${digest%% *}
    printf '%s\t%s\t%s\n' "$mtime" "$cache/${digest}-${mtime}.jpg" "$path" >> "$plan_file"
done < "$list_file"

# Перший прохід: усе, що вже закешовано, віддаємо негайно.
while IFS='	' read -r mtime thumb path; do
    if [ -f "$thumb" ]; then
        printf '%s\t%s\n' "$path" "$thumb"
    fi
done < "$plan_file"

# Другий прохід: докодовуємо лише відсутні мініатюри.
while IFS='	' read -r mtime thumb path; do
    [ -f "$thumb" ] && continue

    thumb_tmp="$cache/.tmp.$$.jpg"
    ffmpeg -nostdin -v error -y -i "$path" \
        -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
        -frames:v 1 -q:v 4 "$thumb_tmp" 2>/dev/null &
    ffmpeg_pid=$!

    if wait "$ffmpeg_pid"; then
        ffmpeg_pid=""
        mv -f "$thumb_tmp" "$thumb"
        thumb_tmp=""
        printf '%s\t%s\n' "$path" "$thumb"
    else
        ffmpeg_pid=""
        rm -f "$thumb_tmp"
        thumb_tmp=""
        # Битий або нечитабельний файл лишається у списку з порожнім
        # прев'ю: вибір шпалери все одно має бути можливим.
        printf '%s\t\n' "$path"
    fi
done < "$plan_file"
