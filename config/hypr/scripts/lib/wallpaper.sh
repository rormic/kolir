#!/bin/sh
# Wallpaper backend state and dispatch shared by the kolir scripts.
#
# Two engines own the desktop:
#   awww      still images (the historical default);
#   mpvpaper  looping video wallpapers.
#
# The choice and the last applied file of each kind live in
# ~/.cache/quickshell/wallpaper.json, written by set-wallpaper.sh and
# wallpaper-backend.sh (the only writers):
#   {"backend":"awww","image":"/…/a.jpg","video":"/…/b.mp4"}
# The shell's WallpaperService only reads it, so QML and the scripts cannot
# disagree about which engine is active.
#
# `backend` is the preference. Resolution still verifies reality: a backend of
# mpvpaper whose process is not playing falls back to awww, so a stale state
# file (or a video that failed) can never leave generate-colors.sh without a
# source.
#
# Sourced by zsh and sh callers, so keep it POSIX. Callers must source
# lib/awww.sh and lib/mpvpaper.sh first: the dispatchers below call both.

kolir_wallpaper_state_file() {
	printf '%s/quickshell/wallpaper.json\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# $1 = key. Prints the string value, or nothing when the file/key is absent.
kolir_wallpaper_state_get() {
	state_file=$(kolir_wallpaper_state_file)
	[ -r "$state_file" ] || return 0

	KOLIR_WALLPAPER_FILE=$state_file KOLIR_WALLPAPER_KEY=$1 python3 -c '
import json, os, sys

try:
    with open(os.environ["KOLIR_WALLPAPER_FILE"], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    sys.exit(0)

value = data.get(os.environ.get("KOLIR_WALLPAPER_KEY", "")) if isinstance(data, dict) else None
if isinstance(value, str):
    sys.stdout.write(value)
' 2>/dev/null
}

# $1 = backend (awww|mpvpaper), $2 = image path, $3 = video path.
# One-line compact JSON, replaced atomically so a reader never sees a torn file.
kolir_wallpaper_state_write() {
	state_file=$(kolir_wallpaper_state_file)
	if ! mkdir -p -- "${state_file%/*}"; then
		echo "wallpaper state: cannot create ${state_file%/*}" >&2
		return 1
	fi

	KOLIR_WALLPAPER_FILE=$state_file \
		KOLIR_WALLPAPER_BACKEND=$1 \
		KOLIR_WALLPAPER_IMAGE=$2 \
		KOLIR_WALLPAPER_VIDEO=$3 \
		python3 -c '
import json, os, tempfile

path = os.environ["KOLIR_WALLPAPER_FILE"]
data = {
    "backend": os.environ.get("KOLIR_WALLPAPER_BACKEND", "awww"),
    "image": os.environ.get("KOLIR_WALLPAPER_IMAGE", ""),
    "video": os.environ.get("KOLIR_WALLPAPER_VIDEO", ""),
}
directory = os.path.dirname(path) or "."
fd, temporary = tempfile.mkstemp(prefix=".wallpaper.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, separators=(",", ":"))
        handle.write("\n")
    os.replace(temporary, path)
except Exception:
    try:
        os.unlink(temporary)
    except OSError:
        pass
    raise
' 2>/dev/null || {
		echo "wallpaper state: could not write $state_file" >&2
		return 1
	}
}

# Prints awww or mpvpaper; unknown/missing state resolves to awww.
kolir_wallpaper_backend() {
	backend=$(kolir_wallpaper_state_get backend)
	case $backend in
		mpvpaper) printf 'mpvpaper\n' ;;
		*) printf 'awww\n' ;;
	esac
}

# True for the video extensions mpvpaper can play (case-insensitive).
kolir_wallpaper_is_video() {
	name=$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')
	case $name in
		*.mp4 | *.webm | *.mkv | *.mov | *.m4v | *.avi) return 0 ;;
	esac
	return 1
}

# Prints image or video.
kolir_wallpaper_kind() {
	if kolir_wallpaper_is_video "$1"; then
		printf 'video\n'
	else
		printf 'image\n'
	fi
}

# $1 = monitor. Prints the path of the wallpaper currently being displayed:
# the video when mpvpaper is really running, otherwise awww's image (with the
# saved image as a fallback for a stopped daemon).
kolir_wallpaper_source() {
	monitor=${1:-DP-1}

	if [ "$(kolir_wallpaper_backend)" = "mpvpaper" ]; then
		video=$(kolir_wallpaper_state_get video)
		if [ -n "$video" ] && [ -r "$video" ] && kolir_mpvpaper_is_running "$video" "$monitor"; then
			printf '%s\n' "$video"
			return 0
		fi
	fi

	if kolir_awww_wallpaper_path "$monitor"; then
		return 0
	fi

	image=$(kolir_wallpaper_state_get image)
	if [ -n "$image" ] && [ -r "$image" ]; then
		printf '%s\n' "$image"
		return 0
	fi

	return 1
}

# $1 = video path. Extracts (and caches) one frame for Matugen. The cache key
# includes the mtime, so an edited video gets a new frame.
kolir_wallpaper_frame() {
	video=${1:-}
	if [ ! -r "$video" ]; then
		echo "wallpaper frame: video is not readable: '${video:-<empty>}'" >&2
		return 1
	fi
	if ! command -v ffmpeg >/dev/null 2>&1; then
		echo "wallpaper frame: ffmpeg is required to sample colors from a video wallpaper" >&2
		return 1
	fi

	mtime=$(stat -c '%Y' -- "$video" 2>/dev/null) || mtime=0
	digest=$(printf '%s\n%s\n' "$video" "$mtime" | sha1sum) || return 1
	digest=${digest%% *}

	frame_dir=${XDG_CACHE_HOME:-$HOME/.cache}/kolir/wallpaper-frames
	frame=$frame_dir/$digest.jpg
	if [ -r "$frame" ]; then
		printf '%s\n' "$frame"
		return 0
	fi
	if ! mkdir -p -- "$frame_dir"; then
		echo "wallpaper frame: cannot create $frame_dir" >&2
		return 1
	fi

	temporary=$frame.tmp.$$.jpg
	# One second in avoids a black fade-in; very short clips fall back to the
	# first frame.
	if ! ffmpeg -nostdin -v error -y -ss 1 -i "$video" \
		-frames:v 1 -q:v 2 "$temporary" 2>/dev/null || [ ! -s "$temporary" ]; then
		if ! ffmpeg -nostdin -v error -y -i "$video" \
			-frames:v 1 -q:v 2 "$temporary" 2>/dev/null || [ ! -s "$temporary" ]; then
			rm -f "$temporary"
			echo "wallpaper frame: could not extract a frame from '$video'" >&2
			return 1
		fi
	fi
	if ! mv -f "$temporary" "$frame"; then
		rm -f "$temporary"
		echo "wallpaper frame: could not save $frame" >&2
		return 1
	fi

	printf '%s\n' "$frame"
}

# $1 = monitor. Prints an image suitable for Matugen: the still wallpaper, or a
# cached frame of the active video.
kolir_wallpaper_image() {
	source_path=$(kolir_wallpaper_source "$1") || return 1
	if kolir_wallpaper_is_video "$source_path"; then
		kolir_wallpaper_frame "$source_path"
	else
		printf '%s\n' "$source_path"
	fi
}
