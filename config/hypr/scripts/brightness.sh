#!/bin/sh
# Яскравість: внутрішня панель (brightnessctl) + зовнішній монітор
# (ddcutil через Quickshell, тому зміна клавішами показує OSD).
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
