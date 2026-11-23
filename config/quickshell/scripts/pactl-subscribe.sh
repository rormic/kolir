#!/bin/sh
# pactl-subscribe.sh — один підписник на події PulseAudio/PipeWire.
#
# Quickshell запускає `pactl subscribe` як дочірній процес Quickshell.Io
# Process, але завершення самого Quickshell не завершує дітей: pactl переходить
# під PID 1 і далі тримає клієнтське підключення до pipewire-pulse. Тому кожен
# перезапуск оболонки додавав ще одного підписника; після кількох десятків
# рестартів сервер починає відмовляти новим клієнтам ("too many client
# application connections"), і `pactl -f json list ...` повертає порожній
# вивід. Новий підписник спершу зупиняє підписника, що лишився від попередньої
# оболонки, і лише потім заступає на його місце.

set -eu

# Порівнюємо повний argv, щоб зупинити лише `pactl subscribe`, а не одноразові
# виклики pactl (list, get-*, set-*), які можуть виконуватися в той самий час.
# Один `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі); знайдений pid усе одно звіряється з /proc/<pid>/cmdline.
pids=$(pgrep -f -- '^(.*/)?pactl subscribe$' 2>/dev/null) || pids=""
for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    args=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    [ "$#" -eq 2 ] || continue
    [ "${1##*/}" = "pactl" ] || continue
    [ "$2" = "subscribe" ] || continue
    kill "$pid" 2>/dev/null || true
done

# Дати старому підписнику відпустити клієнтський слот, перш ніж зайняти новий.
sleep 0.2

exec pactl subscribe
