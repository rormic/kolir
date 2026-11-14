#!/bin/sh
# screen-record.sh — перемикач запису області екрана.
#
# Перше натискання SUPER+R: вибір області через slurp і старт запису.
# Повторне натискання: зупинка, фіналізація mp4 і сповіщення зі шляхом.
#
# Основний рекордер — wf-recorder (працює з NVIDIA/Hyprland). Якщо його немає,
# використовується wl-screenrec. Частота кадрів за замовчуванням дорівнює
# частоті оновлення монітора; KOLIR_REC_FPS=60 примусово повертає 60 fps.
#
# Стан зберігається у $XDG_RUNTIME_DIR/kolir/, щоб індикатор Quickshell
# (config/quickshell/rec/RecordingIndicator.qml) знав, що запис іде.

set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_DIR="$RUNTIME_DIR/kolir"
PID_FILE="$STATE_DIR/record.pid"
STARTED_FILE="$STATE_DIR/record.started"
OUT_FILE="$STATE_DIR/record.file"
STATE_FILE="$STATE_DIR/recording.json"
LOCK_FILE="$STATE_DIR/record.lock"
LOG_FILE="$STATE_DIR/recorder.log"

REC_DIR="${KOLIR_REC_DIR:-$HOME/Videos/Recordings}"
KOLIR_DIR="${KOLIR_DIR:-$HOME/.local/share/kolir}"
QS_CONFIG="$KOLIR_DIR/config/quickshell"
FPS="${KOLIR_REC_FPS:-}"

mkdir -p "$STATE_DIR" || exit 1

# Одночасні виклики (наприклад, швидке подвійне натискання) не мають
# запускати два записи або два slurp.
exec 9>"$LOCK_FILE" || exit 1
if ! flock -n 9; then
	exit 0
fi

ipc() {
	qs -p "$QS_CONFIG" ipc call recording "$@" >/dev/null 2>&1 || true
}

notify() {
	notify-send -a kolir "$@" >/dev/null 2>&1 || true
}

write_state() {
	# $1 = true/false, $2 = started epoch, $3 = output file,
	# $4 = corner, $5 = monitor name.
	# Пишемо на місце, щоб inotify-вотчер FileView у Quickshell не втратив inode.
	printf '{"active":%s,"started":%s,"file":"%s","corner":"%s","monitor":"%s"}\n' \
		"$1" "$2" "$3" "$4" "$5" >"$STATE_FILE"
}

cleanup_files() {
	rm -f "$PID_FILE" "$STARTED_FILE" "$OUT_FILE"
}

is_recording() {
	[ -f "$PID_FILE" ] || return 1
	pid=$(cat "$PID_FILE" 2>/dev/null)
	[ -n "$pid" ] || return 1
	kill -0 "$pid" 2>/dev/null || return 1

	# Захист від повторного використання PID іншим процесом.
	cmd=$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null) || return 1
	case "$cmd" in
	*wf-recorder* | *wl-screenrec*) return 0 ;;
	*) return 1 ;;
	esac
}

# Частота оновлення монітора, на якому лежить центр зони запису.
# Потрібна, щоб за замовчуванням записувати з рідною частотою екрана
# (тут 180 Гц), а не фіксовані 60 fps. KOLIR_REC_FPS перевизначає.
detect_fps() {
	region="$1"
	hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys

region = sys.argv[1]
pos, size = region.split(" ", 1)
rx, ry = (int(v) for v in pos.split(","))
rw, rh = (int(v) for v in size.split("x"))
rcx, rcy = rx + rw / 2, ry + rh / 2

try:
    monitors = json.load(sys.stdin)
except Exception:
    monitors = []

mon = next(
    (
        m
        for m in monitors
        if int(m.get("x", 0)) <= rcx < int(m.get("x", 0)) + int(m.get("width", 0))
        and int(m.get("y", 0)) <= rcy < int(m.get("y", 0)) + int(m.get("height", 0))
    ),
    next((m for m in monitors if m.get("focused")), monitors[0] if monitors else None),
)

print(round(float(mon.get("refreshRate", 60))) if mon else 60)
' "$region" 2>/dev/null
}

# Вибирає кут екрана, який не перетинається із зоною запису, щоб індикатор
# гарантовано не потрапив у відео. Повертає "monitor corner".
indicator_corner() {
	region="$1"
	hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys

region = sys.argv[1]
pos, size = region.split(" ", 1)
rx, ry = (int(v) for v in pos.split(","))
rw, rh = (int(v) for v in size.split("x"))
rcx, rcy = rx + rw / 2, ry + rh / 2

try:
    monitors = json.load(sys.stdin)
except Exception:
    print(" top-right")
    sys.exit(0)

if not monitors:
    print(" top-right")
    sys.exit(0)

focused = next((m for m in monitors if m.get("focused")), monitors[0])

# Монітор, на якому лежить центр зони запису.
target = next(
    (
        m
        for m in monitors
        if int(m.get("x", 0)) <= rcx < int(m.get("x", 0)) + int(m.get("width", 0))
        and int(m.get("y", 0)) <= rcy < int(m.get("y", 0)) + int(m.get("height", 0))
    ),
    focused,
)

# Найкращий варіант для кількох моніторів — інший монітор: тоді індикатор
# точно не потрапить у кадр.
others = [m for m in monitors if m is not target]
if others:
    mon = focused if focused is not target else others[0]
    print(mon.get("name", ""), "top-right")
    sys.exit(0)

mon = target
mx, my = int(mon.get("x", 0)), int(mon.get("y", 0))
sw, sh = int(mon.get("width", 1920)), int(mon.get("height", 1080))

W, H, M, TOP = 160, 24, 10, 36
corners = {
    "top-right":    (sw - M - W, TOP),
    "top-left":     (M, TOP),
    "bottom-right": (sw - M - W, sh - M - H),
    "bottom-left":  (M, sh - M - H),
}

def overlaps(cx, cy):
    # локальні координати зони запису відносно монітора
    lx, ly = rx - mx, ry - my
    return not (cx + W <= lx or cx >= lx + rw or cy + H <= ly or cy >= ly + rh)

corner = next((name for name, (cx, cy) in corners.items() if not overlaps(cx, cy)), "top-right")
print(mon.get("name", ""), corner)
' "$region"
}

stop_recording() {
	pid=$(cat "$PID_FILE" 2>/dev/null)
	out=$(cat "$OUT_FILE" 2>/dev/null)

	# Прибираємо pid-файл одразу, щоб watchdog не сприйняв штатну зупинку
	# за аварійне завершення рекордера.
	rm -f "$PID_FILE"

	if [ -n "$pid" ]; then
		# SIGINT — штатний шлях рекордера: дописати контейнер і вийти.
		kill -INT "$pid" 2>/dev/null

		i=0
		while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do
			sleep 0.1
			i=$((i + 1))
		done

		if kill -0 "$pid" 2>/dev/null; then
			kill -TERM "$pid" 2>/dev/null
			sleep 0.5
			kill -KILL "$pid" 2>/dev/null
		fi
	fi

	cleanup_files
	write_state false 0 "" "top-right" ""
	ipc stopped "$out"

	if [ -n "$out" ] && [ -s "$out" ]; then
		notify "Recording saved" "$out"
	else
		notify -u critical "Recording failed" "Файл не створено. Лог: $LOG_FILE"
	fi
}

find_recorder() {
	if [ -n "${KOLIR_RECORDER:-}" ]; then
		if [ -x "$KOLIR_RECORDER" ]; then
			echo "$KOLIR_RECORDER"
			return
		fi
		if command -v "$KOLIR_RECORDER" >/dev/null 2>&1; then
			command -v "$KOLIR_RECORDER"
			return
		fi
	fi
	if command -v wf-recorder >/dev/null 2>&1; then
		command -v wf-recorder
		return
	fi
	if [ -x "$HOME/.local/bin/wf-recorder" ]; then
		echo "$HOME/.local/bin/wf-recorder"
		return
	fi
	if command -v wl-screenrec >/dev/null 2>&1; then
		command -v wl-screenrec
		return
	fi
}

start_recording() {
	region=$(slurp 2>/dev/null) || exit 0
	[ -n "$region" ] || exit 0

	# За замовчуванням — частота монітора (180 Гц), а не 60.
	fps=${FPS:-$(detect_fps "$region")}
	case "$fps" in
	'' | *[!0-9]*) fps=60 ;;
	esac

	recorder=$(find_recorder)
	if [ -z "$recorder" ]; then
		notify -u critical "Recording failed" "Не знайдено wf-recorder або wl-screenrec"
		exit 1
	fi

	mkdir -p "$REC_DIR" || {
		notify -u critical "Recording failed" "Не вдалося створити теку $REC_DIR"
		exit 1
	}

	base="$REC_DIR/rec_$(date +%Y-%m-%d_%H-%M-%S)"
	out="$base.mp4"
	n=1
	while [ -e "$out" ]; do
		out="${base}_$n.mp4"
		n=$((n + 1))
	done
	started=$(date +%s)
	corner_info=$(indicator_corner "$region")
	mon_name=${corner_info%% *}
	corner=${corner_info##* }
	[ -n "$corner" ] || corner="top-right"

	# Системний звук: монітор джерела default sink. Якщо його немає —
	# записуємо без звуку, щоб не зірвати сам запис.
	mon=""
	sink=$(pactl get-default-sink 2>/dev/null)
	if [ -n "$sink" ]; then
		candidate="$sink.monitor"
		if pactl list short sources 2>/dev/null | awk -v m="$candidate" '$2 == m { found = 1 } END { exit !found }'; then
			mon="$candidate"
		fi
	fi

	case "$recorder" in
	*wf-recorder)
		set -- -g "$region" -f "$out" -r "$fps"
		if [ -n "$mon" ]; then
			set -- "$@" --audio="$mon"
		fi
		# wf-recorder конвертує RGB у YUV за BT.601 в обмеженому діапазоні,
		# але без явних тегів пише "unknown"/"bt470bg". Через це плеєри
		# можуть показувати відео темнішим або зі зсувом кольорів.
		set -- "$@" \
			-p colorspace=bt470bg \
			-p color_primaries=bt709 \
			-p color_trc=bt709 \
			-p color_range=tv
		# Апаратний H.264 на NVIDIA, якщо доступний; інакше — libx264.
		if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_nvenc '; then
			set -- "$@" -c h264_nvenc -p preset=p5 -p tune=hq -p b:v=20M
		fi
		;;
	*)
		set -- -g "$region" -f "$out"
		if [ -n "$mon" ]; then
			set -- "$@" --audio --audio-device "$mon"
		fi
		;;
	esac

	# 9>&- — не успадковувати flock-дескриптор, інакше рекордер триматиме
	# блокування і повторний SUPER+R не зможе зупинити запис.
	setsid "$recorder" "$@" 9>&- >"$LOG_FILE" 2>&1 &
	pid=$!

	# Дати процесу шанс одразу впасти (зайнятий пристрій, немає кодера тощо).
	sleep 0.25
	if ! kill -0 "$pid" 2>/dev/null; then
		cleanup_files
		write_state false 0 "" "top-right" ""
		ipc stopped ""
		notify -u critical "Recording failed to start" "$(tail -n 3 "$LOG_FILE" 2>/dev/null)"
		exit 1
	fi

	echo "$pid" >"$PID_FILE"
	echo "$started" >"$STARTED_FILE"
	echo "$out" >"$OUT_FILE"
	write_state true "$started" "$out" "$corner" "$mon_name"
	ipc started "$started" "$out" "$corner" "$mon_name"

	# Якщо рекордер упаде сам — прибрати індикатор і повідомити про помилку.
	(
		while kill -0 "$pid" 2>/dev/null; do
			sleep 1
		done
		if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$pid" ]; then
			cleanup_files
			write_state false 0 "" "top-right" ""
			ipc stopped ""
			notify -u critical "Recording stopped unexpectedly" "Лог: $LOG_FILE"
		fi
	) 9>&- >/dev/null 2>&1 &

	# Стартове сповіщення не показуємо: індикатор уже сигналізує про запис,
	# а нотифікація могла б потрапити у відео.
}

if is_recording; then
	stop_recording
else
	# pid-файл міг лишитися після аварійного завершення — прибираємо.
	cleanup_files
	start_recording
fi
