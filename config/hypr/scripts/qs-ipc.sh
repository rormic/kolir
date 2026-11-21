#!/bin/sh
# qs-ipc.sh — forward an IPC call to the Quickshell instance running from the
# active kolir root.
#
# Usage:
#   qs-ipc.sh <target> <method> [args...]
#
# Example (Hyprland bind):
#   sh ~/.config/hypr/scripts/qs-ipc.sh launcher toggle

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/root.sh"

if ! ROOT=$(kolir_root "$SCRIPT_DIR"); then
	echo "qs-ipc.sh: could not locate the kolir root; set KOLIR_ROOT" >&2
	exit 1
fi

exec qs -p "$ROOT/config/quickshell" ipc call "$@"
