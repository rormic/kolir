#!/bin/sh
# Monitor geometry and refresh-rate helpers for screen-record.sh. Sourced
# after the recorder state variables are defined; all names and behaviour
# match the original script.

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
