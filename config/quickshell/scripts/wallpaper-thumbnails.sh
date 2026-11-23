#!/bin/sh
# wallpaper-thumbnails.sh — список бібліотеки шпалер і кешовані 16:9 мініатюри.
#
# Використання: wallpaper-thumbnails.sh <wallpaper-dir> <cache-dir> [image|video]
#
# Третій аргумент обирає набір файлів: `image` (типово) показує зображення для
# awww, `video` — відео для mpvpaper. Для відео мініатюрою стає кадр на першій
# секунді (короткі кліпи віддають перший кадр), тому сітка виглядає так само,
# як із зображеннями.
#
# Друкує по одному запису на рядок, розділяючи поля табуляцією:
#   dir<TAB><шлях-до-підтеки>
#   total<TAB><кількість-файлів>
#   <шлях-до-файлу><TAB><шлях-до-мініатюри>
#   <шлях-до-відео><TAB><шлях-до-мініатюри><TAB>video
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

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <wallpaper-dir> <cache-dir> [image|video]" >&2
    exit 2
fi

src=$1
cache=$2
mode=${3:-image}

case $mode in
    image | video) ;;
    *)
        echo "wallpaper-thumbnails.sh: unknown mode '$mode' (expected image or video)" >&2
        exit 2
        ;;
esac

mkdir -p "$cache"

# Зупиняємо воркер попередньої оболонки (або інший режим того самого каталогу:
# новий воркер завжди замінює старий). Порівнюємо повний argv, щоб не зачепити
# разовий ffmpeg чи редактор, який просто згадує цей скрипт.
# Один `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі). Шаблон звужує пошук до воркерів цього скрипта, а кожен знайдений pid
# усе одно звіряється з /proc/<pid>/cmdline, перш ніж його зупинити.
pids=$(pgrep -f -- '^(.*/)?sh .*wallpaper-thumbnails\.sh( |$)' 2>/dev/null) || pids=""
for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    args=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline") || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    { [ "$#" -eq 4 ] || [ "$#" -eq 5 ]; } || continue
    [ "${1##*/}" = "sh" ] || continue
    [ "${2##*/}" = "wallpaper-thumbnails.sh" ] || continue
    [ "$3" = "$src" ] || continue
    [ "$4" = "$cache" ] || continue
    kill "$pid" 2>/dev/null || true
done

list_file="$cache/.list.$$"
dir_file="$cache/.dirs.$$"
plan_file="$cache/.plan.$$"
thumb_tmp=""
ffmpeg_pid=""

cleanup() {
    rm -f "$list_file" "$dir_file" "$plan_file"
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

# Підтеки для навігації: видимі каталоги першого рівня, без прихованих.
find "$src" -mindepth 1 -maxdepth 1 -type d ! -name '.*' \
    -print 2>/dev/null | LC_ALL=C sort > "$dir_file" || true

while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    printf 'dir\t%s\n' "$dir"
done < "$dir_file"

# Ті самі розширення, що й у random-wallpaper.sh і lib/wallpaper.sh, щоб
# список, випадковий вибір і рушій бачили однаковий набір файлів. mtime
# друкується поруч зі шляхом: табуляція молодша за будь-який байт шляху, тому
# сортування цілих рядків дає той самий порядок, що й сортування самих шляхів,
# а план нижче не робить окремий `stat` на кожен файл.
if [ "$mode" = "video" ]; then
    find "$src" -maxdepth 1 -type f \
        \( -name '*.mp4' -o -name '*.webm' -o -name '*.mkv' -o -name '*.mov' \
        -o -name '*.m4v' -o -name '*.avi' \) \
        -printf '%p\t%T@\n' 2>/dev/null | LC_ALL=C sort > "$list_file" || true
else
    find "$src" -maxdepth 1 -type f \
        \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' \) \
        -printf '%p\t%T@\n' 2>/dev/null | LC_ALL=C sort > "$list_file" || true
fi

total=$(wc -l < "$list_file" | tr -d ' ')
printf 'total\t%s\n' "$total"

: > "$plan_file"
# The plan is written through an open descriptor: a SIGTERM from a folder
# switch runs cleanup (which unlinks the plan) while this loop may still be
# between iterations, and writing to the still-open unlinked inode must not
# produce an error.
#
# The plan is built in one python3 pass: the mtime already comes from
# `find -printf`, and sha1(path\nmtime) is hashed in that same process, so
# there is no `stat` or `sha1sum` fork per file any more. The plan line and
# the cache name are unchanged.
exec 3>> "$plan_file"
python3 -c '
import hashlib, os, sys

cache = os.fsencode(sys.argv[1])
out = sys.stdout.buffer
for line in sys.stdin.buffer:
    line = line.rstrip(b"\n")
    if not line:
        continue
    path, _, stamp = line.rpartition(b"\t")
    mtime = stamp.split(b".", 1)[0] or b"0"
    digest = hashlib.sha1(path + b"\n" + mtime + b"\n").hexdigest().encode()
    out.write(mtime + b"\t" + cache + b"/" + digest + b"-" + mtime + b".jpg\t"
              + path + b"\n")
' "$cache" < "$list_file" >&3
exec 3>&-

record() {
    # $1 = path, $2 = thumbnail (may be empty)
    if [ "$mode" = "video" ]; then
        printf '%s\t%s\tvideo\n' "$1" "$2"
    else
        printf '%s\t%s\n' "$1" "$2"
    fi
}

# Перший прохід: усе, що вже закешовано, віддаємо негайно.
while IFS='	' read -r mtime thumb path; do
    if [ -f "$thumb" ]; then
        record "$path" "$thumb"
    fi
done < "$plan_file"

# Другий прохід: докодовуємо лише відсутні мініатюри.
while IFS='	' read -r mtime thumb path; do
    [ -f "$thumb" ] && continue

    thumb_tmp="$cache/.tmp.$$.jpg"
    if [ "$mode" = "video" ]; then
        # Одна секунда всередині кліпу уникає чорного fade-in. Дуже короткий
        # ролик може не мати кадру на цій позиції — тоді беремо перший.
        ffmpeg -nostdin -v error -y -ss 1 -i "$path" \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -frames:v 1 -q:v 4 "$thumb_tmp" 2>/dev/null &
        ffmpeg_pid=$!
        if ! wait "$ffmpeg_pid" || [ ! -s "$thumb_tmp" ]; then
            ffmpeg_pid=""
            rm -f "$thumb_tmp"
            ffmpeg -nostdin -v error -y -i "$path" \
                -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
                -frames:v 1 -q:v 4 "$thumb_tmp" 2>/dev/null &
            ffmpeg_pid=$!
            if ! wait "$ffmpeg_pid"; then
                ffmpeg_pid=""
                rm -f "$thumb_tmp"
                thumb_tmp=""
                # Битий або нечитабельний файл лишається у списку з порожнім
                # прев'ю: вибір шпалери все одно має бути можливим.
                record "$path" ""
                continue
            fi
        fi
        ffmpeg_pid=""
    else
        ffmpeg -nostdin -v error -y -i "$path" \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -frames:v 1 -q:v 4 "$thumb_tmp" 2>/dev/null &
        ffmpeg_pid=$!

        if ! wait "$ffmpeg_pid"; then
            ffmpeg_pid=""
            rm -f "$thumb_tmp"
            thumb_tmp=""
            record "$path" ""
            continue
        fi
        ffmpeg_pid=""
    fi

    mv -f "$thumb_tmp" "$thumb"
    thumb_tmp=""
    record "$path" "$thumb"
done < "$plan_file"
