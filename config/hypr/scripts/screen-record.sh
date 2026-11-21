#!/bin/sh
# screen-record.sh — запис області екрана з одноразовими налаштуваннями.
#
# Використання:
#   screen-record.sh                    — перемикач: старт (slurp) / стоп;
#   screen-record.sh --setup            — відкрити меню налаштувань Quickshell;
#   screen-record.sh --start [опції]    — одразу стартувати запис.
#
# Опції --start діють лише на цей запуск і ніде не зберігаються:
#   --fps auto|30|60|120|180
#   --quality low|medium|high|max
#   --codec h264|hevc|av1
#   --audio system|mic|both|none
#   --area region|full
#
# Основний рекордер — wf-recorder (працює з NVIDIA/Hyprland). Якщо його немає,
# використовується wl-screenrec. Частота кадрів за замовчуванням дорівнює
# частоті оновлення монітора; KOLIR_REC_FPS=60 примусово повертає 60 fps.
#
# Стан зберігається у $XDG_RUNTIME_DIR/kolir/, щоб індикатор у статусбарі
# (config/quickshell/bar/components/RecordingStatus.qml) знав, що запис іде.

set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_DIR="$RUNTIME_DIR/kolir"
PID_FILE="$STATE_DIR/record.pid"
STARTED_FILE="$STATE_DIR/record.started"
OUT_FILE="$STATE_DIR/record.file"
STATE_FILE="$STATE_DIR/recording.json"
LOCK_FILE="$STATE_DIR/record.lock"
LOG_FILE="$STATE_DIR/recorder.log"
AUDIO_MODULES_FILE="$STATE_DIR/record.modules"

REC_DIR="${KOLIR_REC_DIR:-$HOME/Videos/Recordings}"
KOLIR_DIR="${KOLIR_DIR:-$HOME/.local/share/kolir}"
QS_CONFIG="$KOLIR_DIR/config/quickshell"
FPS="${KOLIR_REC_FPS:-}"
MIX_SINK="kolir_rec_mix"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/screen-record/audio.sh"

# Одноразові налаштування (живуть тільки до кінця цього запуску скрипта).
ACTION="toggle"
OPT_FPS="auto"
OPT_QUALITY="medium"
OPT_CODEC="h264"
OPT_AUDIO="system"
OPT_AREA="region"

while [ $# -gt 0 ]; do
	case "$1" in
	--setup) ACTION="setup" ;;
	--start) ACTION="start" ;;
	--fps | --quality | --codec | --audio | --area)
		opt="$1"
		shift
		[ $# -gt 0 ] || break
		case "$opt" in
		--fps) OPT_FPS="$1" ;;
		--quality) OPT_QUALITY="$1" ;;
		--codec) OPT_CODEC="$1" ;;
		--audio) OPT_AUDIO="$1" ;;
		--area) OPT_AREA="$1" ;;
		esac
		;;
	-h | --help)
		sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	esac
	shift
done

case "$OPT_FPS" in
auto | "") OPT_FPS="auto" ;;
*[!0-9]*) OPT_FPS="auto" ;;
esac
case "$OPT_QUALITY" in
low | medium | high | max) ;;
*) OPT_QUALITY="medium" ;;
esac
case "$OPT_CODEC" in
h264 | hevc | av1) ;;
*) OPT_CODEC="h264" ;;
esac
case "$OPT_AUDIO" in
system | mic | both | none) ;;
*) OPT_AUDIO="system" ;;
esac
case "$OPT_AREA" in
region | full) ;;
*) OPT_AREA="region" ;;
esac

mkdir -p "$STATE_DIR" || exit 1

# Одночасні виклики (наприклад, швидке подвійне натискання) не мають
# запускати два записи або два slurp. Не виходимо зовсім мовчки: інакше
# здається, що гаряча клавіша зламалася (саме так було зі завислим slurp).
exec 9>"$LOCK_FILE" || exit 1
if ! flock -n 9; then
	echo "$(date '+%F %T') another instance holds $LOCK_FILE, exiting" >>"$LOG_FILE"
	if [ "$ACTION" != "setup" ]; then
		notify-send -a kolir "Recording" "Інший запис або вибір області вже активний." >/dev/null 2>&1 || true
	fi
	exit 0
fi

ipc() {
	qs -p "$QS_CONFIG" ipc call recording "$@" >/dev/null 2>&1 || true
}

notify() {
	notify-send -a kolir "$@" >/dev/null 2>&1 || true
}

write_state() {
	# $1 = true/false, $2 = started epoch, $3 = output file.
	# Пишемо на місце, щоб inotify-вотчер FileView у Quickshell не втратив inode.
	printf '{"active":%s,"started":%s,"file":"%s"}\n' \
		"$1" "$2" "$3" >"$STATE_FILE"
}

cleanup_files() {
	cleanup_audio_mix
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

# Геометрія монітора з фокусом — для запису всього екрана без slurp.
focused_region() {
	hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys

try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(1)

mon = next((m for m in monitors if m.get("focused")), monitors[0] if monitors else None)
if not mon:
    sys.exit(1)

print("%s,%s %sx%s" % (mon.get("x", 0), mon.get("y", 0), mon.get("width", 0), mon.get("height", 0)))
' 2>/dev/null
}

# Назва монітора з фокусом — для wf-recorder -o у режимі повного екрана.
focused_monitor_name() {
	hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys

try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(1)

mon = next((m for m in monitors if m.get("focused")), monitors[0] if monitors else None)
if mon:
    print(mon.get("name", ""))
' 2>/dev/null
}

has_encoder() {
	ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"
}

# Наявність енкодера в ffmpeg ще не означає, що GPU його підтримує
# (наприклад, av1_nvenc є в збірці, але не на всіх відеокартах).
encoder_usable() {
	case "$1" in
	*nvenc)
		ffmpeg -hide_banner -loglevel error \
			-f lavfi -i color=c=black:s=256x256:r=1 -frames:v 1 \
			-c:v "$1" -f null - >/dev/null 2>&1
		;;
	*) return 0 ;;
	esac
}

encoder_for() {
	case "$OPT_CODEC" in
	hevc)
		if has_encoder hevc_nvenc && encoder_usable hevc_nvenc; then
			echo hevc_nvenc
		elif has_encoder libx265; then
			echo libx265
		fi
		;;
	av1)
		if has_encoder av1_nvenc && encoder_usable av1_nvenc; then
			echo av1_nvenc
		elif has_encoder libsvtav1; then
			echo libsvtav1
		elif has_encoder libaom-av1; then
			echo libaom-av1
		fi
		;;
	*)
		if has_encoder h264_nvenc && encoder_usable h264_nvenc; then
			echo h264_nvenc
		elif has_encoder libx264; then
			echo libx264
		fi
		;;
	esac
}

quality_bitrate() {
	case "$OPT_QUALITY" in
	low) echo "8M" ;;
	high) echo "40M" ;;
	max) echo "80M" ;;
	*) echo "20M" ;;
	esac
}

quality_crf() {
	# $1 = encoder
	case "$1" in
	libx264) case "$OPT_QUALITY" in low) echo 28 ;; medium) echo 23 ;; high) echo 18 ;; max) echo 14 ;; esac ;;
	libx265) case "$OPT_QUALITY" in low) echo 30 ;; medium) echo 26 ;; high) echo 22 ;; max) echo 18 ;; esac ;;
	*) case "$OPT_QUALITY" in low) echo 38 ;; medium) echo 32 ;; high) echo 26 ;; max) echo 20 ;; esac ;;
	esac
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
	write_state false 0 ""
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
	# Панель могла лишитися видимою (наприклад, SUPER+R при відкритому
	# меню). Ховаємо її перед slurp: інакше вона потрапить у вибір/відео
	# і утримуватиме клавіатурний фокус.
	qs -p "$QS_CONFIG" ipc call recordingSetup close >/dev/null 2>&1 || true

	# Зона запису: або вибір через slurp, або весь екран.
	mon_name=""
	if [ "$OPT_AREA" = "full" ]; then
		region=$(focused_region)
		if [ -z "$region" ]; then
			notify -u critical "Recording failed" "Не вдалося визначити монітор"
			exit 1
		fi
		mon_name=$(focused_monitor_name)
	else
		# </dev/null обов'язковий: якщо stdin — не термінал (а відкритий
		# пайп, як у Quickshell Process), slurp чекає на нього замість
		# показу оверлея. Через це він тримав flock і блокував усі
		# наступні натискання SUPER+R.
		region=$(slurp </dev/null 2>>"$LOG_FILE") || exit 0
		[ -n "$region" ] || exit 0
	fi

	# За замовчуванням — частота монітора (180 Гц), а не 60.
	fps="$OPT_FPS"
	[ "$fps" = "auto" ] && fps="$FPS"
	[ -n "$fps" ] || fps=$(detect_fps "$region")
	case "$fps" in
	'' | *[!0-9]*) fps=60 ;;
	esac

	recorder=$(find_recorder)
	if [ -z "$recorder" ]; then
		notify -u critical "Recording failed" "Не знайдено wf-recorder або wl-screenrec"
		exit 1
	fi

	encoder=$(encoder_for)
	if [ -z "$encoder" ]; then
		notify -u critical "Recording failed" "Не знайдено відповідний відеокодер ($OPT_CODEC)"
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

	# Звук: система / мікрофон / обидва через тимчасовий мікшер / без звуку.
	mon=""
	case "$OPT_AUDIO" in
	mic)
		mon=$(default_microphone)
		if [ -z "$mon" ]; then
			notify "Recording" "Мікрофон не знайдено — запис без звуку"
		fi
		;;
	both)
		mon=$(setup_audio_mix)
		if [ -z "$mon" ]; then
			mon=$(default_sink_monitor)
			notify "Recording" "Не вдалося змішати звук — записую лише системний"
		fi
		;;
	none) mon="" ;;
	*) mon=$(default_sink_monitor) ;;
	esac

	case "$recorder" in
	*wf-recorder)
		set -- -f "$out" -r "$fps"
		if [ "$OPT_AREA" = "full" ] && [ -n "$mon_name" ]; then
			set -- "$@" -o "$mon_name"
		else
			set -- "$@" -g "$region"
		fi
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

		case "$encoder" in
		*nvenc)
			# wf-recorder передає -p у avcodec_open2, тому ключ саме "b",
			# а не ffmpeg-синтаксис "b:v" (інакше бітрейт ігнорується).
			set -- "$@" -c "$encoder" -p preset=p5 -p tune=hq -p "b=$(quality_bitrate)"
			;;
		*)
			set -- "$@" -c "$encoder" -p "crf=$(quality_crf "$encoder")"
			;;
		esac
		;;
	*)
		set -- -f "$out"
		[ "$OPT_AREA" = "region" ] && set -- "$@" -g "$region"
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
		write_state false 0 ""
		ipc stopped ""
		notify -u critical "Recording failed to start" "$(tail -n 3 "$LOG_FILE" 2>/dev/null)"
		exit 1
	fi

	echo "$pid" >"$PID_FILE"
	echo "$started" >"$STARTED_FILE"
	echo "$out" >"$OUT_FILE"
	write_state true "$started" "$out"
	ipc started "$started" "$out"

	# Якщо рекордер упаде сам — прибрати індикатор і повідомити про помилку.
	(
		while kill -0 "$pid" 2>/dev/null; do
			sleep 1
		done
		if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$pid" ]; then
			cleanup_files
			write_state false 0 ""
			ipc stopped ""
			notify -u critical "Recording stopped unexpectedly" "Лог: $LOG_FILE"
		fi
	) 9>&- >/dev/null 2>&1 &

	# Стартове сповіщення не показуємо: індикатор уже сигналізує про запис,
	# а нотифікація могла б потрапити у відео.
}

case "$ACTION" in
setup)
	if is_recording; then
		notify "Recording" "Запис уже йде. Зупиніть його перед зміною налаштувань."
		exit 0
	fi
	if ! qs -p "$QS_CONFIG" ipc call recordingSetup open >/dev/null 2>&1; then
		notify -u critical "Recording setup" "Не вдалося відкрити меню Quickshell"
	fi
	;;
start)
	if is_recording; then
		notify "Recording" "Запис уже йде."
		exit 0
	fi
	cleanup_files
	start_recording
	;;
*)
	if is_recording; then
		stop_recording
	else
		# pid-файл міг лишитися після аварійного завершення — прибираємо.
		cleanup_files
		start_recording
	fi
	;;
esac
