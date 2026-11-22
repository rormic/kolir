#!/bin/sh
# screenshot-region.sh — скриншот області з замороженим кадром.
#
# SUPER+X: знімає фокусований монітор у PNG, показує його на весь екран через
# Quickshell-оверлей `screenshot`, дає slurp намалювати область поверх нього і
# обрізає знімок до вибраної ділянки. Поки триває вибір, вміст позаду не
# рухається.
#
# Якщо оболонка не відповідає або оверлей не з'являється, повертається старе
# поведення: grim -g "$(slurp)" на живому екрані.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/root.sh"

if ! ROOT=$(kolir_root "$SCRIPT_DIR"); then
	echo "screenshot-region.sh: could not locate the kolir root; set KOLIR_ROOT" >&2
	exit 1
fi

QS_CONFIG="$ROOT/config/quickshell"

. "$SCRIPT_DIR/lib/monitors.sh"

TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
# Збережена копія для панелі Capture History; KOLIR_SHOT_DIR збігається з
# ShellPaths.screenshotDir у Quickshell.
SHOT_DIR="${KOLIR_SHOT_DIR:-$HOME/Pictures/Screenshots}"
SHOT=$(mktemp --suffix=.png "$TMP_DIR/kolir-screenshot-XXXXXX") || exit 1
CROP=""
cleanup() {
	[ -n "$CROP" ] && rm -f "$CROP"
	rm -f "$SHOT"
	# На випадок, якщо скрипт перервали до завершення вибору.
	if command -v qs >/dev/null 2>&1; then
		qs -p "$QS_CONFIG" ipc call screenshot close >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# Одночасно має працювати лише один вибір: повторний SUPER+X не закриває
# оверлей першого, поки користувач ще виділяє область.
#
# Дірка 9 — дескриптор flock. Дочірні процеси, які переживають скрипт
# (wl-copy демонизується, slurp чекає на виділення), не повинні її
# успадковувати: інакше вони тримали б lock після виходу скрипта, і наступні
# натискання SUPER+X мовчки виходили на flock. Тому 9>&- у всіх довгоживучих
# викликах.
LOCK_DIR="$TMP_DIR/kolir"
LOCK_FILE="$LOCK_DIR/screenshot.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
exec 9>"$LOCK_FILE" || exit 1
if ! flock -n 9; then
	exit 0
fi

notify_error() {
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -a kolir "$1" "$2" >/dev/null 2>&1 || true
	fi
}

# Копія завершеного знімка для панелі Capture History. Копіювання в буфер
# обміну лишається головною дією; невдалий запис не має ламати скриншот.
save_shot() {
	[ -n "${1:-}" ] || return 0
	mkdir -p "$SHOT_DIR" 2>/dev/null || return 0
	base="$SHOT_DIR/shot_$(date +%Y-%m-%d_%H-%M-%S)"
	out="$base.png"
	n=1
	while [ -e "$out" ]; do
		out="${base}_$n.png"
		n=$((n + 1))
	done
	cp -- "$1" "$out" 2>/dev/null || true
}

mon=$(kolir_focused_monitor_name)
if [ -z "$mon" ]; then
	notify_error "Screenshot failed" "Не вдалося визначити монітор"
	exit 1
fi

# -l 0 (без стиснення) — найшвидший шлях: на повному 2560x1440 PNG-стиснення
# коштує ~100 мс, тоді як незжатий файл пишеться у tmpfs за ~40 мс.
if ! grim -o "$mon" -l 0 "$SHOT" 2>/dev/null; then
	notify_error "Screenshot failed" "grim не зміг зробити знімок"
	exit 1
fi

# Показати заморожений кадр. Зображення в оверлеї декодується синхронно,
# тож чекаємо лише на мапінг шару в hyprctl layers, перш ніж запускати slurp.
overlay_ready=0
if command -v qs >/dev/null 2>&1; then
	if qs -p "$QS_CONFIG" ipc call screenshot open "$SHOT" >/dev/null 2>&1; then
		i=0
		while [ "$i" -lt 100 ]; do
			if hyprctl layers -j 2>/dev/null | grep -q '"screenshot"'; then
				overlay_ready=1
				break
			fi
			sleep 0.005
			i=$((i + 1))
		done
	fi
fi

if [ "$overlay_ready" -eq 1 ]; then
	region=$(slurp -f '%X,%Y %Wx%H' </dev/null 9>&- 2>/dev/null) || region=""
	qs -p "$QS_CONFIG" ipc call screenshot close >/dev/null 2>&1 || true

	if [ -z "$region" ]; then
		# Escape або помилка slurp: вибір скасовано, нічого не робимо.
		exit 0
	fi
else
	# Оверлей недоступний (наприклад, оболонка не запущена): старе живе
	# виділення, як до появи замороженого кадру.
	live_region=$(slurp </dev/null 9>&- 2>/dev/null) || live_region=""
	if [ -n "$live_region" ]; then
		live_shot=$(mktemp --suffix=.png "$TMP_DIR/kolir-screenshot-live-XXXXXX") || live_shot=""
		if [ -n "$live_shot" ]; then
			if grim -g "$live_region" "$live_shot" 2>/dev/null; then
				wl-copy -t image/png <"$live_shot" 9>&-
				save_shot "$live_shot"
			fi
			rm -f "$live_shot"
		fi
	fi
	exit 0
fi

# region = "X,Y WxH" відносно фокусованого монітора.
x=${region%%,*}
rest=${region#*,}
y=${rest%% *}
size=${rest#* }
w=${size%x*}
h=${size#*x}

digits_only() {
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

if ! digits_only "$x" || ! digits_only "$y" || ! digits_only "$w" || ! digits_only "$h"; then
	exit 0
fi
[ "$w" -gt 0 ] && [ "$h" -gt 0 ] || exit 0

# slurp повертає логічні координати, а PNG — фізичні пікселі монітора.
# Розрахунок масштабу відкладено до після вибору: він не має стояти на
# критичному шляху між натисканням і появою замороженого кадру.
scale=$(hyprctl -j monitors 2>/dev/null | KOLIR_MON_NAME="$mon" python3 -c '
import json, os, sys
try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(1)
mon = next((m for m in monitors if m.get("name") == os.environ.get("KOLIR_MON_NAME")), None)
if not mon:
    sys.exit(1)
print(int(round(float(mon.get("scale", 1)))))
' 2>/dev/null) || scale=1
case "$scale" in
0 | '' | *[!0-9]*) scale=1 ;;
esac

x=$((x * scale))
y=$((y * scale))
w=$((w * scale))
h=$((h * scale))

if command -v ffmpeg >/dev/null 2>&1; then
	CROP=$(mktemp --suffix=.png "$TMP_DIR/kolir-screenshot-crop-XXXXXX") || CROP=""
	if [ -n "$CROP" ]; then
		if ffmpeg -y -loglevel error -i "$SHOT" -vf "crop=$w:$h:$x:$y" -frames:v 1 "$CROP" 9>&- 2>/dev/null; then
			wl-copy -t image/png < "$CROP" 9>&-
			save_shot "$CROP"
		fi
	fi
else
	# Без ffmpeg обрізати знімок нічим: беремо область з живого екрана.
	geom=$(kolir_focused_monitor_geometry)
	mon_x=${geom%%,*}
	rest=${geom#*,}
	mon_y=${rest%% *}
	gx=$((mon_x + x / scale))
	gy=$((mon_y + y / scale))
	live_shot=$(mktemp --suffix=.png "$TMP_DIR/kolir-screenshot-live-XXXXXX") || live_shot=""
	if [ -n "$live_shot" ]; then
		if grim -g "$gx,$gy ${w}x${h}" "$live_shot" 2>/dev/null; then
			wl-copy -t image/png <"$live_shot" 9>&-
			save_shot "$live_shot"
		fi
		rm -f "$live_shot"
	fi
fi
