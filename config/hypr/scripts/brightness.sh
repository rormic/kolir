#!/bin/sh
# Яскравість: внутрішня панель і зовнішній монітор.
#
# Обидва бекенди тепер належать BrightnessService (Quickshell): сервіс пише в
# brightnessctl для панелі й у ddcutil для монітора, тому OSD і віджет у барі
# завжди синхронні з екраном. Скрипт лише передає крок через IPC; якщо оболонка
# не відповідає, він напряму змінює внутрішню панель, щоб клавіші працювали і
# без запущеного Quickshell.
#
# Використання:
#   brightness.sh up    — збільшити на 5%
#   brightness.sh down  — зменшити на 5%

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/root.sh"

# KOLIR_DIR was the old override name; keep it working for existing setups.
if [ -n "${KOLIR_DIR:-}" ] && [ -z "${KOLIR_ROOT:-}" ]; then
	KOLIR_ROOT=$KOLIR_DIR
	export KOLIR_ROOT
fi

if ! ROOT=$(kolir_root "$SCRIPT_DIR"); then
	echo "brightness.sh: could not locate the kolir root; set KOLIR_ROOT" >&2
	exit 1
fi
QS_CONFIG="$ROOT/config/quickshell"

case "${1:-}" in
	up | down) ACTION=$1 ;;
	*)
		echo "usage: $(basename "$0") {up|down}" >&2
		exit 1
		;;
esac

if ! qs -p "$QS_CONFIG" ipc call brightness "$ACTION" >/dev/null 2>&1; then
	case "$ACTION" in
		up) brightnessctl -c backlight -e4 -n2 set 5%+ ;;
		down) brightnessctl -c backlight -e4 -n2 set 5%- ;;
	esac
fi
