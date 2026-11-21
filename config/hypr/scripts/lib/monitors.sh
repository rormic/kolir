#!/bin/sh
# Shared monitor selection for kolir scripts.
#
# Resolution order:
#   1. $KOLIR_MONITOR, when set (explicit override for multi-monitor setups);
#   2. the focused monitor reported by `hyprctl monitors -j`;
#   3. the first monitor in that list;
#   4. DP-1 only in kolir_monitor_name, as the last-resort default when
#      Hyprland cannot be queried at all (the author's machine uses DP-1).
#
# Sourced by both zsh (wallpaper/color scripts) and sh (screen-record.sh)
# callers, so keep it POSIX.

_kolir_monitor_pick() {
	# $1 = name|geometry. Prints nothing when hyprctl reports no monitors.
	KOLIR_MON_FIELD="$1" python3 -c '
import json, os, sys

field = os.environ.get("KOLIR_MON_FIELD", "name")
try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(1)

mon = next((m for m in monitors if m.get("focused")), monitors[0] if monitors else None)
if not mon:
    sys.exit(1)

if field == "geometry":
    print("%s,%s %sx%s" % (mon.get("x", 0), mon.get("y", 0), mon.get("width", 0), mon.get("height", 0)))
else:
    print(mon.get("name", ""))
' 2>/dev/null
}

_kolir_monitor_by_name() {
	# $1 = monitor name, $2 = name|geometry.
	KOLIR_MON_FIELD="$2" KOLIR_MON_NAME="$1" python3 -c '
import json, os, sys

field = os.environ.get("KOLIR_MON_FIELD", "name")
want = os.environ.get("KOLIR_MON_NAME", "")
try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit(1)

mon = next((m for m in monitors if m.get("name") == want), None)
if not mon:
    sys.exit(1)

if field == "geometry":
    print("%s,%s %sx%s" % (mon.get("x", 0), mon.get("y", 0), mon.get("width", 0), mon.get("height", 0)))
else:
    print(mon.get("name", ""))
' 2>/dev/null
}

# Focused monitor, honouring $KOLIR_MONITOR. Empty when hyprctl has no answer.
kolir_focused_monitor_name() {
	if [ -n "${KOLIR_MONITOR:-}" ]; then
		printf '%s\n' "$KOLIR_MONITOR"
		return 0
	fi
	hyprctl -j monitors 2>/dev/null | _kolir_monitor_pick name
}

# Same selection as above, but with DP-1 as the final fallback.
kolir_monitor_name() {
	name=$(kolir_focused_monitor_name)
	[ -n "$name" ] || name="DP-1"
	printf '%s\n' "$name"
}

# "x,y wxh" of the focused monitor, honouring $KOLIR_MONITOR. Empty when the
# monitor cannot be resolved.
kolir_focused_monitor_geometry() {
	if [ -n "${KOLIR_MONITOR:-}" ]; then
		hyprctl -j monitors 2>/dev/null | _kolir_monitor_by_name "$KOLIR_MONITOR" geometry
		return 0
	fi
	hyprctl -j monitors 2>/dev/null | _kolir_monitor_pick geometry
}

# Geometry of kolir_monitor_name (falls back to the focused monitor when the
# override names an unknown output, so the lock background still gets a size).
kolir_monitor_geometry() {
	name=$(kolir_monitor_name)
	geometry=$(hyprctl -j monitors 2>/dev/null | _kolir_monitor_by_name "$name" geometry)
	if [ -z "$geometry" ]; then
		geometry=$(hyprctl -j monitors 2>/dev/null | _kolir_monitor_pick geometry)
	fi
	printf '%s\n' "$geometry"
}
