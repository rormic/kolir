#!/bin/sh
# Яскравість: внутрішня панель (brightnessctl) + зовнішній монітор
# (ddcutil через Quickshell, тому зміна клавішами показує OSD).
#
# Використання:
#   brightness.sh up    — збільшити на 5%
#   brightness.sh down  — зменшити на 5%

set -u

KOLIR_DIR="${KOLIR_DIR:-$HOME/.local/share/kolir}"
QS_CONFIG="$KOLIR_DIR/config/quickshell"

case "$1" in
	up)
		brightnessctl -e4 -n2 set 5%+
		qs -p "$QS_CONFIG" ipc call brightness up >/dev/null 2>&1 || true
		;;
	down)
		brightnessctl -e4 -n2 set 5%-
		qs -p "$QS_CONFIG" ipc call brightness down >/dev/null 2>&1 || true
		;;
	*)
		echo "usage: $(basename "$0") {up|down}" >&2
		exit 1
		;;
esac
