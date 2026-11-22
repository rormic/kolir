#!/usr/bin/env bash
# Flips the desktop between light and dark. The Appearance page owns the mode
# (auto/light/dark); a manual flip always resolves to an explicit mode so the
# next color regeneration cannot silently switch back to matugen's smart mode.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/theme.sh"

STATE_FILE=$(kolir_theme_state_file)

current=$(cat "$STATE_FILE" 2>/dev/null)
[[ "$current" == "light" ]] && new="dark" || new="light"

kolir_sync_appearance_mode "$new"
kolir_apply_theme_mode "$new"

zsh "$SCRIPT_DIR/generate-colors.sh"
