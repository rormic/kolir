#!/bin/sh
# capture-history.sh — список скріншотів і записів та кешовані 16:9 постери.
#
# Використання: capture-history.sh <cache-dir> <limit> <dir>...
#
# Друкує по одному запису на рядок, розділяючи поля табуляцією:
#   total<TAB><кількість-елементів>
#   <шлях><TAB><шлях-до-постера><TAB>image|video<TAB><mtime>
#
# Каталоги скануються без рекурсії й об'єднуються; елементи сортуються за
# mtime (новіші першими) і обрізаються до <limit>. Постер генерується ffmpeg
# першим кадром відео (0.5 с) або самою картинкою. Ключ кешу містить mtime
# джерела, як у wallpaper-thumbnails.sh: змінений файл отримує новий постер,
# незмінені ніколи не перекодовуються.
#
# Quickshell не забирає своїх дітей після завершення, тому воркер спершу
# зупиняє ідентичний воркер, що лишився від попередньої оболонки (той самий
# кеш і ліміт). Постер пишеться в тимчасовий файл і перейменовується, тож
# скасування не лишає обрізаний JPEG.

set -eu

if [ "$#" -lt 3 ]; then
    echo "usage: $0 <cache-dir> <limit> <dir>..." >&2
    exit 2
fi

cache=$1
limit=$2
shift 2

mkdir -p "$cache"

has_ffmpeg=1
command -v ffmpeg >/dev/null 2>&1 || has_ffmpeg=0

# Зупиняємо воркер попередньої оболонки. Порівнюємо повний argv, щоб не
# зачепити разовий ffmpeg чи редактор, який просто згадує цей скрипт. Функція
# потрібна, щоб `set --` не з'їв позиційні параметри зі списком каталогів.
# Один `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі). Шаблон звужує пошук до воркерів цього скрипта, а кожен знайдений pid
# усе одно звіряється з /proc/<pid>/cmdline, перш ніж його зупинити.
kill_previous() {
    pids=$(pgrep -f -- '^(.*/)?sh .*capture-history\.sh( |$)' 2>/dev/null) || pids=""
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
        [ "$#" -ge 4 ] || continue
        [ "${1##*/}" = "sh" ] || continue
        [ "${2##*/}" = "capture-history.sh" ] || continue
        [ "$3" = "$cache" ] || continue
        [ "$4" = "$limit" ] || continue
        kill "$pid" 2>/dev/null || true
    done
}

kill_previous

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

# Один список на всі каталоги: find дає mtime і шлях, sort тримає найновіші
# першими, head застосовує ліміт панелі. Колонка mtime лишається в списку, щоб
# план нижче не робив окремий `stat` на кожен файл.
: > "$list_file"
for dir in "$@"; do
    [ -d "$dir" ] || continue
    find "$dir" -mindepth 1 -maxdepth 1 -type f \
        \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \
        -o -name '*.webp' -o -name '*.gif' \
        -o -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' \
        -o -name '*.mov' \) \
        -printf '%T@\t%p\n' 2>/dev/null || true
done | LC_ALL=C sort -rn -k1,1 | head -n "$limit" > "$list_file"

total=$(wc -l < "$list_file" | tr -d ' ')
printf 'total\t%s\n' "$total"

# План будується одним проходом python3: mtime вже є з `find -printf`, а
# sha1(path\nmtime) рахується в тому самому процесі, тож на кожен файл більше
# немає окремих `stat` і `sha1sum`. Формат рядка плану не змінився.
: > "$plan_file"
# План пишеться через відкритий дескриптор: SIGTERM під час зміни каталогу
# виконує cleanup (який видаляє plan) між ітераціями, і запис у вже
# відкритий inode не повинен давати помилку.
exec 3>> "$plan_file"
python3 -c '
import hashlib, os, sys

cache = os.fsencode(sys.argv[1])
out = sys.stdout.buffer
for line in sys.stdin.buffer:
    line = line.rstrip(b"\n")
    if not line:
        continue
    stamp, _, path = line.partition(b"\t")
    mtime = stamp.split(b".", 1)[0] or b"0"
    if path.endswith((b".mp4", b".mkv", b".webm", b".mov")):
        kind = b"video"
    else:
        kind = b"image"
    digest = hashlib.sha1(path + b"\n" + mtime + b"\n").hexdigest().encode()
    out.write(mtime + b"\t" + kind + b"\t" + cache + b"/" + digest
              + b"-" + mtime + b".jpg\t" + path + b"\n")
' "$cache" < "$list_file" >&3
exec 3>&-

encode_thumb() {
    # $1 = source, $2 = output, $3 = image|video
    if [ "$3" = "video" ]; then
        ffmpeg -nostdin -v error -y -ss 0.5 -i "$1" -frames:v 1 \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -q:v 4 "$2" 2>/dev/null
    else
        ffmpeg -nostdin -v error -y -i "$1" -frames:v 1 \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -q:v 4 "$2" 2>/dev/null
    fi
}

# Перший прохід: усе, що вже закешовано, віддаємо негайно.
while IFS='	' read -r mtime kind thumb path; do
    if [ -f "$thumb" ]; then
        printf '%s\t%s\t%s\t%s\n' "$path" "$thumb" "$kind" "$mtime"
    fi
done < "$plan_file"

# Другий прохід: докодовуємо лише відсутні постери.
while IFS='	' read -r mtime kind thumb path; do
    [ -f "$thumb" ] && continue

    if [ "$has_ffmpeg" -eq 0 ]; then
        printf '%s\t\t%s\t%s\n' "$path" "$kind" "$mtime"
        continue
    fi

    thumb_tmp="$cache/.tmp.$$.jpg"
    encode_thumb "$path" "$thumb_tmp" "$kind" &
    ffmpeg_pid=$!

    if wait "$ffmpeg_pid"; then
        ffmpeg_pid=""
        mv -f "$thumb_tmp" "$thumb"
        thumb_tmp=""
        printf '%s\t%s\t%s\t%s\n' "$path" "$thumb" "$kind" "$mtime"
    else
        ffmpeg_pid=""
        rm -f "$thumb_tmp"
        thumb_tmp=""
        # Битий або нечитабельний файл лишається у списку з порожнім
        # постером: картка все одно має бути видимою й відкриваною.
        printf '%s\t\t%s\t%s\n' "$path" "$kind" "$mtime"
    fi
done < "$plan_file"
