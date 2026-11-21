#!/usr/bin/env zsh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/awww.sh"

WALLPAPER_PATH=$1

# Cancelled picker (select-wallpaper.sh passes an empty argument).
if [ -z "$WALLPAPER_PATH" ]; then
    exit 0
fi

if [ ! -r "$WALLPAPER_PATH" ]; then
    echo "set-wallpaper.sh: wallpaper file not found or unreadable: '${WALLPAPER_PATH}'" >&2
    exit 1
fi

kolir_awww_check || exit 1

if ! awww img "$WALLPAPER_PATH" -t random --transition-fps 180; then
    version=$(kolir_awww_version)
    [ -n "$version" ] || version="unknown"
    echo "set-wallpaper.sh: 'awww img' failed for '${WALLPAPER_PATH}' (awww ${version})" >&2
    exit 1
fi
