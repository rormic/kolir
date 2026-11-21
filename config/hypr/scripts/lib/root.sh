#!/bin/sh
# Shared kolir root resolution for the Hyprland helper scripts.
#
# The installed desktop links ~/.config/hypr/scripts to
# <root>/config/hypr/scripts, so $0 still ends in config/hypr/scripts when a
# script runs through the symlink. The physical parent of that directory is the
# active root. This works both for a git checkout and for the future
# /usr/share/kolir package layout.
#
# Resolution order:
#   1. $KOLIR_ROOT (explicit override; also used by the tests);
#   2. the checkout/package containing this script;
#   3. /usr/share/kolir (distribution package layout).
#
# Usage: . lib/root.sh; root=$(kolir_root "$SCRIPT_DIR") || exit 1
# The optional argument is the caller's script directory; it defaults to the
# directory of $0. Keep this file POSIX sh: screen-record.sh, qs-ipc.sh and the
# other helpers are executed with sh.

kolir_root() {
	_kolir_dir=${1:-$(dirname -- "$0")}
	_kolir_dir=$(CDPATH= cd -- "$_kolir_dir" 2>/dev/null && pwd -P) || _kolir_dir=""

	# 1. Explicit override.
	if [ -n "${KOLIR_ROOT:-}" ]; then
		printf '%s\n' "$KOLIR_ROOT"
		return 0
	fi

	# 2. Physical root above config/hypr/scripts (<root>/config/hypr/scripts
	#    -> <root>). qs-ipc.sh and launch-shell.sh live in the same directory.
	if [ -n "$_kolir_dir" ]; then
		case $_kolir_dir in
		*/config/hypr/scripts)
			_kolir_root=${_kolir_dir%/config/hypr/scripts}
			if [ -f "$_kolir_root/config/hypr/hyprland.lua" ]; then
				printf '%s\n' "$_kolir_root"
				return 0
			fi
			;;
		esac
	fi

	# 3. Distribution package layout.
	if [ -f /usr/share/kolir/config/hypr/hyprland.lua ]; then
		printf '%s\n' /usr/share/kolir
		return 0
	fi

	return 1
}
