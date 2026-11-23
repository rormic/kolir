#!/usr/bin/env zsh
# Picks a random wallpaper for the active backend (images for awww, videos for
# mpvpaper) and applies it. A backend with no matching files falls back to an
# image so the bind never does nothing.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/monitors.sh"
. "$SCRIPT_DIR/lib/awww.sh"
. "$SCRIPT_DIR/lib/mpvpaper.sh"
. "$SCRIPT_DIR/lib/wallpaper.sh"

WALLPAPER_DIR="$HOME/Pictures/wallpaper"

list_images() {
    find "$WALLPAPER_DIR" -type f \
        \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' \) \
        2>/dev/null
}

list_videos() {
    find "$WALLPAPER_DIR" -type f \
        \( -name '*.mp4' -o -name '*.webm' -o -name '*.mkv' -o -name '*.mov' \
        -o -name '*.m4v' -o -name '*.avi' \) 2>/dev/null
}

if [ "$(kolir_wallpaper_backend)" = "mpvpaper" ]; then
    bg=$(list_videos | shuf -n 1)
    if [ -z "$bg" ]; then
        echo "random-wallpaper.sh: the video backend is active but '$WALLPAPER_DIR' has no videos; falling back to an image" >&2
        bg=$(list_images | shuf -n 1)
    fi
else
    bg=$(list_images | shuf -n 1)
fi

if [ -z "$bg" ]; then
    echo "random-wallpaper.sh: no wallpapers in '$WALLPAPER_DIR'" >&2
    exit 1
fi

sh "$SCRIPT_DIR/set-wallpaper.sh" "$bg" || exit 1
sh "$SCRIPT_DIR/generate-colors.sh"
