#!/bin/sh
# wallpaper-backend.sh — switch the active wallpaper engine.
#
# Usage: wallpaper-backend.sh <awww|mpvpaper>
#
# The state is written by this script and by set-wallpaper.sh only; the shell
# reads it through WallpaperService. Switching to mpvpaper replays the last
# video (or waits for one if none was picked yet); switching to awww stops the
# video and replays the last image. Running it again with the active backend
# is a no-op when the engine is already in the right state, so the shell can
# call it on every start to restore a video without restarting a live player.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/monitors.sh"
. "$SCRIPT_DIR/lib/awww.sh"
. "$SCRIPT_DIR/lib/mpvpaper.sh"
. "$SCRIPT_DIR/lib/wallpaper.sh"

if [ "$#" -ne 1 ]; then
    echo "usage: wallpaper-backend.sh <awww|mpvpaper>" >&2
    exit 2
fi

BACKEND=$1
case $BACKEND in
    awww | mpvpaper) ;;
    *)
        echo "wallpaper-backend.sh: unknown backend '$BACKEND' (expected 'awww' or 'mpvpaper')" >&2
        exit 2
        ;;
esac

CURRENT=$(kolir_wallpaper_backend)
IMAGE=$(kolir_wallpaper_state_get image)
VIDEO=$(kolir_wallpaper_state_get video)

if [ "$BACKEND" = "mpvpaper" ]; then
    if [ -n "$VIDEO" ] && [ -r "$VIDEO" ]; then
        kolir_mpvpaper_check || exit 1
        MONITOR=$(kolir_monitor_name)
        if ! kolir_mpvpaper_is_running "$VIDEO" "$MONITOR"; then
            if ! kolir_mpvpaper_restart "$MONITOR" "$VIDEO"; then
                echo "wallpaper-backend.sh: could not start the video wallpaper '$VIDEO' on '$MONITOR'" >&2
                exit 1
            fi
        fi
    fi
else
    # awww stays behind the video, so stopping the player reveals the last
    # image again. When an image exists, validate it and the daemon first: a
    # failed restore must leave the video playing. With no image yet (a fresh
    # machine, or the first wallpaper was a video) the switch still succeeds so
    # the picker can show the Images grid; the desktop is briefly empty until
    # one is picked.
    if [ "$CURRENT" != "awww" ] && [ -n "$IMAGE" ] && [ -r "$IMAGE" ]; then
        kolir_awww_check || exit 1
        if ! awww img "$IMAGE" -t random --transition-fps 180; then
            echo "wallpaper-backend.sh: could not restore the image wallpaper '$IMAGE'" >&2
            exit 1
        fi
    fi
    kolir_mpvpaper_stop
fi

kolir_wallpaper_state_write "$BACKEND" "$IMAGE" "$VIDEO" || exit 1
