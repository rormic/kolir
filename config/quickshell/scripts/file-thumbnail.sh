#!/bin/sh
# file-thumbnail.sh — одна кешована 16:9 мініатюра для портального файлового
# вибору.
#
# Використання: file-thumbnail.sh <cache-dir> <path>
#
# Друкує рівно один запис, розділяючи поля табуляцією:
#   <шлях-до-мініатюри><TAB>image|video
#
# Скрипт разовий: FilePicker запускає його лише для плиток, які справді
# з'явилися в сітці, по одному файлу за раз. Тому великий каталог фотографій
# не кодує нічого наперед — кожен виклик або віддає готовий кеш, або створює
# рівно одну мініатюру.
#
# Ключ кешу містить шлях і mtime джерела (sha1): змінений файл отримує нову
# мініатюру, незмінені ніколи не перекодовуються. Розширення збігаються зі
# списками fileIconFor() у FilePicker.qml, тож вибір не запускає ffmpeg для
# аудіо чи архіву, а невідомий тип завершується помилкою ще до запуску.
#
# Зображення дають один кадр, відео — кадр на першій секунді (короткі кліпи
# віддають перший кадр). Мініатюра пишеться в тимчасовий файл і
# перейменовується, а trap зупиняє поточний ffmpeg, тож скасування не лишає
# обрізаний JPEG.

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <cache-dir> <path>" >&2
    exit 2
fi

cache=$1
src=$2

if [ "$src" = "" ] || [ ! -f "$src" ] || [ ! -r "$src" ]; then
    echo "file-thumbnail.sh: not a readable file: $src" >&2
    exit 1
fi

# Розширення береться з basename, як у fileIconFor(): точка в імені каталогу
# не має значення.
base=${src##*/}
ext=$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')

case $ext in
    png | jpg | jpeg | gif | webp | bmp | svg | avif | heic | tiff)
        kind=image
        ;;
    mp4 | mkv | mov | avi | webm | flv | m4v)
        kind=video
        ;;
    *)
        echo "file-thumbnail.sh: unsupported file type: $src" >&2
        exit 1
        ;;
esac

mtime=$(stat -Lc %Y -- "$src" 2>/dev/null) || {
    echo "file-thumbnail.sh: cannot read the file time: $src" >&2
    exit 1
}
digest=$(printf '%s\n%s\n' "$src" "$mtime" | sha1sum) || {
    echo "file-thumbnail.sh: sha1sum is not available" >&2
    exit 1
}
digest=${digest%% *}

mkdir -p "$cache" || {
    echo "file-thumbnail.sh: cannot create the cache directory: $cache" >&2
    exit 1
}

thumb="$cache/$digest-$mtime.jpg"

# Кеш віддається до перевірки ffmpeg: повторний показ каталогу має працювати
# навіть на машині, де ffmpeg уже прибрали.
if [ -s "$thumb" ]; then
    printf '%s\t%s\n' "$thumb" "$kind"
    exit 0
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "file-thumbnail.sh: ffmpeg is not installed" >&2
    exit 1
fi

thumb_tmp="$cache/.tmp.$$.jpg"
ffmpeg_pid=""

cleanup() {
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

# ffmpeg завжди у фоні, щоб trap міг зупинити саме його, а не лише оболонку.
run_ffmpeg() {
    # $1 = image|video, $2 = source, $3 = output
    if [ "$1" = "video" ]; then
        ffmpeg -nostdin -v error -y -ss 1 -i "$2" \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -frames:v 1 -q:v 4 "$3" 2>/dev/null &
    else
        ffmpeg -nostdin -v error -y -i "$2" \
            -vf 'scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
            -frames:v 1 -q:v 4 "$3" 2>/dev/null &
    fi
    ffmpeg_pid=$!
    if wait "$ffmpeg_pid"; then
        ffmpeg_pid=""
        return 0
    fi
    ffmpeg_pid=""
    return 1
}

encoded=0
if [ "$kind" = "video" ]; then
    # Одна секунда всередині кліпу уникає чорного fade-in; дуже короткий ролик
    # може не мати кадру на цій позиції — тоді беремо перший.
    if run_ffmpeg video "$src" "$thumb_tmp" && [ -s "$thumb_tmp" ]; then
        encoded=1
    else
        rm -f "$thumb_tmp"
        if run_ffmpeg image "$src" "$thumb_tmp" && [ -s "$thumb_tmp" ]; then
            encoded=1
        fi
    fi
elif run_ffmpeg image "$src" "$thumb_tmp" && [ -s "$thumb_tmp" ]; then
    encoded=1
fi

if [ "$encoded" -ne 1 ]; then
    rm -f "$thumb_tmp"
    thumb_tmp=""
    echo "file-thumbnail.sh: could not generate a preview: $src" >&2
    exit 1
fi

mv -f "$thumb_tmp" "$thumb"
thumb_tmp=""

printf '%s\t%s\n' "$thumb" "$kind"
