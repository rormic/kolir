#!/bin/sh
# notification-sound.sh — короткий сигнал про нове сповіщення.
#
# У Quickshell немає власного звукового контуру сповіщень, тож оболонка грає
# його сама. Скрипт бере перший доступний програвач і звук freedesktop
# (message-new-instant), а необов'язковий $1 — власний файл звуку з підказки
# `sound-file`. Якщо відтворити не вдалося, про помилку повідомляє через центр
# сповіщень: інакше збій аудіо лишився б непоміченим.

set -eu

# Окреме ім'я застосунку, щоб NotificationService не грала чим саму помилку
# (інакше повідомлення про збій звуку викликало б ще одну спробу відтворення).
app_name=kolir-sound

report_error() {
    msg=$1
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "$app_name" -t 5000 \
            "Помилка звуку сповіщень" "$msg" >/dev/null 2>&1 || true
    else
        echo "notification-sound.sh: $msg" >&2
    fi
}

sound=""
for candidate in \
    /usr/share/sounds/freedesktop/stereo/message-new-instant.oga \
    /usr/share/sounds/freedesktop/stereo/dialog-information.oga \
    /usr/share/sounds/freedesktop/stereo/bell.oga
do
    if [ -f "$candidate" ]; then
        sound="$candidate"
        break
    fi
done

# Власний звук з підказки має пріоритет, але лише якщо файл справді існує.
if [ "$#" -ge 1 ] && [ -n "$1" ] && [ -f "$1" ]; then
    sound="$1"
fi

if [ -n "$sound" ] && command -v paplay >/dev/null 2>&1; then
    player=paplay
elif [ -n "$sound" ] && command -v pw-play >/dev/null 2>&1; then
    player=pw-play
elif command -v canberra-gtk-play >/dev/null 2>&1; then
    # canberra грає за назвою події, тож працює навіть без файлу звуку.
    player=canberra-gtk-play
else
    report_error "Не знайдено жодного програвача (paplay, pw-play, canberra-gtk-play)."
    exit 0
fi

if [ "$player" = "canberra-gtk-play" ]; then
    # canberra не грає довільний файл напряму, але знає той самий звук за
    # назвою події.
    if canberra-gtk-play -i message-new-instant >/dev/null 2>&1; then
        exit 0
    fi

    report_error "canberra-gtk-play не зміг відтворити звук сповіщень."
    exit 0
fi

if "$player" "$sound" >/dev/null 2>&1; then
    exit 0
fi

report_error "$player не зміг відтворити $sound."
exit 0
