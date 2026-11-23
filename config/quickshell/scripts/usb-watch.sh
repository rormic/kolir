#!/bin/sh
# usb-watch.sh — один слухач підключення USB-пристроїв.
#
# Quickshell запускає слухача як дочірній процес Quickshell.Io Process, але
# завершення самого Quickshell не завершує дітей: udevadm monitor переходить
# під PID 1 і далі друкує події. Тому новий слухач спершу зупиняє слухача, що
# лишився від попередньої оболонки, і лише потім заступає на його місце.
#
# Скрипт друкує весь вивід `udevadm monitor --property`; EventSoundService
# шукає в ньому ACTION=add і DEVTYPE=usb_device, щоб грати звук один раз на
# пристрій, а не на кожен його інтерфейс.

set -eu

command -v udevadm >/dev/null 2>&1 || {
    echo "usb-watch.sh: udevadm not found" >&2
    exit 1
}

# Порівнюємо повний argv, щоб зупинити лише ідентичний монітор, а не інший
# udevadm чи іншу оболонку, яка просто згадує цю команду.
for cmdline in /proc/[0-9]*/cmdline; do
    pid=${cmdline#/proc/}
    pid=${pid%/cmdline}
    [ "$pid" = "$$" ] && continue
    [ -r "$cmdline" ] || continue
    # The process may exit between the glob and the read; keep that race quiet.
    args=$( { tr '\0' '\n' < "$cmdline"; } 2>/dev/null ) || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    [ "$#" -eq 5 ] || continue
    [ "${1##*/}" = "udevadm" ] || continue
    [ "$2" = "monitor" ] || continue
    [ "$3" = "--udev" ] || continue
    [ "$4" = "--subsystem-match=usb" ] || continue
    [ "$5" = "--property" ] || continue
    kill "$pid" 2>/dev/null || true
done

exec udevadm monitor --udev --subsystem-match=usb --property
