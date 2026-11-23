#!/bin/sh
# event-sound.sh — короткий звук події оболонки.
#
# Quickshell не має власного звукового контуру, тож оболонка грає короткі
# сигнали сама. Скрипт знає кілька подій і бере для кожної звук із теми
# freedesktop: сповіщення, підключення USB та низький заряд батареї. Якщо
# відтворити не вдалося, про помилку повідомляє через центр сповіщень, інакше
# збій аудіо лишився б непоміченим.
#
# Використання: event-sound.sh <подія> [файл-звуку]
#   notification      message-new-instant
#   usb               device-added
#   battery-low       dialog-warning
#   battery-critical  dialog-error
#
# Необов'язковий файл має пріоритет над звуком теми: так сповіщення з підказки
# `sound-file` грає саме свій звук.

set -eu

# Окреме ім'я застосунку, щоб NotificationService не грав чим саму помилку
# (інакше повідомлення про збій звуку викликало б ще одну спробу відтворення).
app_name=kolir-sound

event=${1:-notification}
custom=${2:-}

case "$event" in
    notification)
        canberra_event=message-new-instant
        default_sound=message-new-instant.oga
        ;;
    usb)
        canberra_event=device-added
        default_sound=device-added.oga
        ;;
    battery-low)
        canberra_event=dialog-warning
        default_sound=dialog-warning.oga
        ;;
    battery-critical)
        canberra_event=dialog-error
        default_sound=dialog-error.oga
        ;;
    *)
        echo "event-sound.sh: невідома подія: $event" >&2
        exit 2
        ;;
esac

report_error() {
    msg=$1
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "$app_name" -t 5000 \
            "Помилка звуку події" "$msg" >/dev/null 2>&1 || true
    else
        echo "event-sound.sh: $msg" >&2
    fi
}

theme_dir=/usr/share/sounds/freedesktop/stereo
sound=""
for candidate in "$theme_dir/$default_sound" "$theme_dir/bell.oga"; do
    if [ -f "$candidate" ]; then
        sound="$candidate"
        break
    fi
done

# Власний звук має пріоритет, але лише якщо файл справді існує.
if [ -n "$custom" ] && [ -f "$custom" ]; then
    sound="$custom"
fi

# Файл граємо через PipeWire, потім PulseAudio, а якщо файлу немає чи обидва
# програвачі недоступні — просимо canberra відтворити подію за назвою.
if [ -n "$sound" ] && command -v pw-play >/dev/null 2>&1; then
    if pw-play "$sound" >/dev/null 2>&1; then
        exit 0
    fi
fi

if [ -n "$sound" ] && command -v paplay >/dev/null 2>&1; then
    if paplay "$sound" >/dev/null 2>&1; then
        exit 0
    fi
fi

if command -v canberra-gtk-play >/dev/null 2>&1; then
    if canberra-gtk-play -i "$canberra_event" >/dev/null 2>&1; then
        exit 0
    fi

    report_error "canberra-gtk-play не зміг відтворити звук «$event»."
    exit 0
fi

report_error "Не знайдено жодного програвача (pw-play, paplay, canberra-gtk-play)."
exit 0
