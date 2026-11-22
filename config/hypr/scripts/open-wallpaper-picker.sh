#!/bin/sh
# open-wallpaper-picker.sh — відкрити панель вибору шпалер у Quickshell.
#
# Гаряча клавіша викликає цей скрипт. Якщо оболонка запущена, IPC відкриває
# панель з сіткою мініатюр. Якщо Quickshell не працює (або IPC недоступний),
# скрипт запускає select-wallpaper.sh, який відкриває Zenity, як раніше.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/root.sh"

if command -v qs >/dev/null 2>&1 \
    && ROOT=$(kolir_root "$SCRIPT_DIR") \
    && qs -p "$ROOT/config/quickshell" ipc call wallpaper toggle >/dev/null 2>&1; then
    exit 0
fi

exec sh "$SCRIPT_DIR/select-wallpaper.sh"
