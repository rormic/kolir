#!/bin/sh
# Apply the light/dark cursor variant that matches the resolved desktop theme.
#
# AppearanceService runs this when the "Cursor follows theme" switch changes and
# once after startup, so a saved choice is live before the next palette
# regeneration. generate-colors.sh and toggle-theme.sh reach the same helper
# through lib/theme.sh. The machine's cursor theme comes from XCURSOR_THEME
# (set in user.lua); only its light/dark token is swapped.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/theme.sh"

force=false
mode=""
for argument in "$@"; do
	case $argument in
		--force) force=true ;;
		light | dark) mode=$argument ;;
	esac
done

theme_file=$(kolir_theme_state_file)
if [ -z "$mode" ] && [ -r "$theme_file" ]; then
	mode=$(tr -d '[:space:]' <"$theme_file")
fi

case $mode in
	light | dark) ;;
	*) exit 0 ;;
esac

kolir_apply_cursor_theme "$mode" "$force"
