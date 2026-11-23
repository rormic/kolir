#!/usr/bin/env zsh
# Zenity fallback used when Quickshell is not running. Images and videos are
# both selectable; set-wallpaper.sh picks the engine from the extension.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_DIR="$HOME/Pictures/wallpaper/"
WALLPAPER_PATH=$(zenity --file-selection --filename="$TARGET_DIR/" \
    --file-filter='Wallpapers | *.jpg *.jpeg *.png *.gif *.mp4 *.webm *.mkv *.mov *.m4v *.avi')

sh "$SCRIPT_DIR/set-wallpaper.sh" "$WALLPAPER_PATH"

sh "$SCRIPT_DIR/generate-colors.sh"
