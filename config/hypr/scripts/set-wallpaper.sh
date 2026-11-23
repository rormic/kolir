#!/usr/bin/env zsh
# Applies one wallpaper. The engine follows the file: images go to awww,
# videos to mpvpaper. The resulting backend and the last path of each kind are
# saved in ~/.cache/quickshell/wallpaper.json for generate-colors.sh and the
# shell's WallpaperService.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/monitors.sh"
. "$SCRIPT_DIR/lib/awww.sh"
. "$SCRIPT_DIR/lib/mpvpaper.sh"
. "$SCRIPT_DIR/lib/wallpaper.sh"

WALLPAPER_PATH=$1

# Cancelled picker (select-wallpaper.sh passes an empty argument).
if [ -z "$WALLPAPER_PATH" ]; then
    exit 0
fi

if [ ! -r "$WALLPAPER_PATH" ]; then
    echo "set-wallpaper.sh: wallpaper file not found or unreadable: '${WALLPAPER_PATH}'" >&2
    exit 1
fi

# Store absolute paths so login restore and state diagnostics never depend on
# the caller's working directory.
WALLPAPER_PATH=$(readlink -f -- "$WALLPAPER_PATH") || exit 1

IMAGE_PATH=$(kolir_wallpaper_state_get image)
VIDEO_PATH=$(kolir_wallpaper_state_get video)

if kolir_wallpaper_is_video "$WALLPAPER_PATH"; then
    kolir_mpvpaper_check || exit 1

    MONITOR=$(kolir_monitor_name)
    if ! kolir_mpvpaper_restart "$MONITOR" "$WALLPAPER_PATH"; then
        echo "set-wallpaper.sh: could not play '${WALLPAPER_PATH}' on '$MONITOR' with mpvpaper" >&2
        exit 1
    fi

    if ! kolir_wallpaper_state_write mpvpaper "$IMAGE_PATH" "$WALLPAPER_PATH"; then
        echo "set-wallpaper.sh: the video is playing, but the wallpaper state could not be saved" >&2
    fi
    exit 0
fi

kolir_awww_check || exit 1

# An image replaces a playing video: mpvpaper draws above awww, so leaving it
# running would hide the new image.
kolir_mpvpaper_stop

if ! awww img "$WALLPAPER_PATH" -t random --transition-fps 180; then
    version=$(kolir_awww_version)
    [ -n "$version" ] || version="unknown"
    echo "set-wallpaper.sh: 'awww img' failed for '${WALLPAPER_PATH}' (awww ${version})" >&2
    exit 1
fi

if ! kolir_wallpaper_state_write awww "$WALLPAPER_PATH" "$VIDEO_PATH"; then
    echo "set-wallpaper.sh: the image is displayed, but the wallpaper state could not be saved" >&2
fi
