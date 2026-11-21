#!/bin/sh
# launch-shell.sh — start the Quickshell config from the active kolir root.
#
# Usage:
#   launch-shell.sh [qs args...]
#
# Example (Hyprland autostart in ~/.config/hypr/user.lua):
#   hl.exec_cmd("sh ~/.config/hypr/scripts/launch-shell.sh")

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/root.sh"

if ! ROOT=$(kolir_root "$SCRIPT_DIR"); then
	echo "launch-shell.sh: could not locate the kolir root; set KOLIR_ROOT" >&2
	exit 1
fi

exec qs -p "$ROOT/config/quickshell" "$@"
