#!/bin/sh
# palette-previews.sh — палітри всіх схем Matugen для поточної шпалери.
#
# Використання: palette-previews.sh <light|dark> <контраст> <файл-кешу>
#
# Шпалера визначається так само, як у generate-colors.sh: спільні
# lib/monitors.sh + lib/awww.sh, тому панель Appearance не дублює логіку
# пошуку awww. Генерація й кеш живуть у palette-previews.py.

set -u

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <light|dark> <contrast> <cache-file>" >&2
    exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
ROOT=$(readlink -f -- "$SCRIPT_DIR/../../..") || exit 1

if ! command -v python3 >/dev/null 2>&1; then
    echo "palette-previews.sh: python3 not found" >&2
    exit 1
fi

if ! command -v matugen >/dev/null 2>&1; then
    echo "palette-previews.sh: matugen not found" >&2
    exit 1
fi

. "$ROOT/config/hypr/scripts/lib/monitors.sh"
. "$ROOT/config/hypr/scripts/lib/awww.sh"

MONITOR=$(kolir_monitor_name)
if ! IMAGE=$(kolir_awww_wallpaper_path "$MONITOR"); then
    echo "palette-previews.sh: no readable wallpaper for monitor '$MONITOR'" >&2
    exit 1
fi

# Mirror generate-colors.sh so the preview uses the same Matugen config
# (custom extraction preferences, fallback color, ...). --dry-run keeps the
# templates untouched.
if [ -n "${KOLIR_MATUGEN_CONFIG:-}" ] && [ -r "$KOLIR_MATUGEN_CONFIG" ]; then
    CONFIG=$KOLIR_MATUGEN_CONFIG
elif [ -r "$HOME/.config/matugen/config.toml" ]; then
    CONFIG=$HOME/.config/matugen/config.toml
else
    CONFIG=$ROOT/config/matugen/config.toml
fi
[ -r "$CONFIG" ] || CONFIG=""

exec python3 "$SCRIPT_DIR/palette-previews.py" \
    --wallpaper "$IMAGE" \
    --mode "$1" \
    --contrast "$2" \
    --cache "$3" \
    --config "$CONFIG"
