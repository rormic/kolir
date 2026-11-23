#!/bin/sh
# mpvpaper lifecycle helpers for video wallpapers.
#
# mpvpaper has no stop command: one process owns one output and lives until it
# is killed. kolir therefore keeps the pid in $XDG_RUNTIME_DIR/kolir so a new
# video (or an image, which stops the engine) can replace it. The runtime dir
# is cleared at logout, so a stale pid can never point at an unrelated process
# after a reboot; the /proc check below is a second guard.
#
# A video is drawn on the background layer above awww, so switching back to an
# image only needs to stop mpvpaper: awww's last image is still behind it.
#
# Sourced by zsh and sh callers, so keep it POSIX. Callers must source this
# file before lib/wallpaper.sh (which dispatches between both engines).

kolir_mpvpaper_version() {
	command -v mpvpaper >/dev/null 2>&1 || return 1
	mpvpaper --version 2>/dev/null | head -n 1
}

kolir_mpvpaper_runtime_dir() {
	printf '%s/kolir\n' "${XDG_RUNTIME_DIR:-/tmp}"
}

kolir_mpvpaper_pidfile() {
	printf '%s/mpvpaper.pid\n' "$(kolir_mpvpaper_runtime_dir)"
}

kolir_mpvpaper_logfile() {
	printf '%s/kolir/mpvpaper.log\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Prints the live pid owned by kolir, or nothing. A pid entry whose process is
# gone, or is not mpvpaper (recycled pid), is discarded.
kolir_mpvpaper_pid() {
	pidfile=$(kolir_mpvpaper_pidfile)
	[ -r "$pidfile" ] || return 1

	pid=$(tr -d '[:space:]' < "$pidfile" 2>/dev/null)
	case $pid in
		'' | *[!0-9]*)
			return 1
			;;
	esac
	[ -d "/proc/$pid" ] || return 1

	args=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline") || return 1
	printf '%s\n' "$args" | grep -q 'mpvpaper' || return 1

	printf '%s\n' "$pid"
}

# $1 = video path, $2 = monitor (both optional). True when the live process is
# playing exactly that file on that output.
kolir_mpvpaper_is_running() {
	pid=$(kolir_mpvpaper_pid) || return 1
	[ -n "${1:-}" ] || return 0

	args=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline") || return 1
	printf '%s\n' "$args" | grep -Fxq -- "$1" || return 1

	if [ -n "${2:-}" ]; then
		printf '%s\n' "$args" | grep -Fxq -- "$2" || return 1
	fi
	return 0
}

kolir_mpvpaper_stop() {
	pidfile=$(kolir_mpvpaper_pidfile)
	pid=$(kolir_mpvpaper_pid) || {
		rm -f "$pidfile"
		return 0
	}

	kill "$pid" 2>/dev/null || true
	wait_count=0
	while [ "$wait_count" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
		sleep 0.1 2>/dev/null || sleep 1
		wait_count=$((wait_count + 1))
	done
	kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
	rm -f "$pidfile"
	return 0
}

# $1 = monitor name, $2 = video path. Starts (or replaces) the engine.
kolir_mpvpaper_start() {
	kolir_mpvpaper_check || return 1

	monitor=${1:-}
	video=${2:-}
	if [ -z "$monitor" ] || [ -z "$video" ]; then
		echo "mpvpaper: a monitor and a video path are required" >&2
		return 1
	fi
	if [ ! -r "$video" ]; then
		echo "mpvpaper: video is not readable: '$video'" >&2
		return 1
	fi

	logfile=$(kolir_mpvpaper_logfile)
	if ! mkdir -p -- "${logfile%/*}"; then
		echo "mpvpaper: cannot create ${logfile%/*}" >&2
		return 1
	fi
	runtime_dir=$(kolir_mpvpaper_runtime_dir)
	if ! mkdir -p -- "$runtime_dir"; then
		echo "mpvpaper: cannot create ${runtime_dir}" >&2
		return 1
	fi

	# no-audio keeps the desktop silent; loop repeats the clip; hwdec offloads
	# decoding when the GPU supports it, panscan crops to fill the output
	# instead of leaving letterbox bars.
	: > "$logfile"
	mpvpaper -o 'no-audio loop hwdec=auto-safe panscan=1.0' \
		"$monitor" "$video" </dev/null >>"$logfile" 2>&1 &
	pid=$!
	if ! printf '%s\n' "$pid" > "$(kolir_mpvpaper_pidfile)"; then
		echo "mpvpaper: could not record the player pid in $(kolir_mpvpaper_pidfile)" >&2
		kill "$pid" 2>/dev/null || true
		return 1
	fi

	# mpvpaper validates the output and the file before creating its surface;
	# give it a moment so a broken start is reported instead of saved.
	sleep 0.4 2>/dev/null || sleep 1
	if ! kill -0 "$pid" 2>/dev/null; then
		rm -f "$(kolir_mpvpaper_pidfile)"
		echo "mpvpaper: failed to start for '$monitor' (log: $logfile):" >&2
		tail -n 3 "$logfile" 2>/dev/null >&2 || true
		return 1
	fi

	return 0
}

# Stops the current process (if any) and plays $2 on $1.
kolir_mpvpaper_restart() {
	kolir_mpvpaper_stop || true
	kolir_mpvpaper_start "$1" "$2"
}

kolir_mpvpaper_check() {
	if ! command -v mpvpaper >/dev/null 2>&1; then
		echo "mpvpaper: command not found; install the mpvpaper package (AUR) to play video wallpapers" >&2
		return 1
	fi
	return 0
}
