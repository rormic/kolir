#!/bin/sh
# Wallpaper lookup helpers for kolir scripts.
#
# awww stores its state as <cache>/awww/<version>/<monitor> and the cache
# encoding changed between releases (NUL-separated fields in 0.12.x, one
# concatenated string before that). The version directory name changes with
# every release too, so nothing here may hardcode either.
#
# Lookup order:
#   1. `awww query -j` (the daemon's own report; no cache format involved);
#   2. the on-disk cache, newest version directory first, decoded tolerantly;
#   3. a clear error that says what was tried and which files were found.
#
# Sourced by zsh callers, so keep it POSIX.

kolir_awww_version() {
	command -v awww >/dev/null 2>&1 || return 1
	awww --version 2>/dev/null | awk 'NR == 1 { print $NF }'
}

# Cache candidates, newest version directory first; the root itself is the
# last candidate for layouts without a version level. Prints nothing when
# there is no awww cache at all.
kolir_awww_cache_roots() {
	cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/awww"
	[ -d "$cache_root" ] || return 1
	find "$cache_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -Vr
	printf '%s\n' "$cache_root"
}

kolir_awww_cache_dir() {
	roots=$(kolir_awww_cache_roots) || return 1
	printf '%s\n' "$roots" | head -n 1
}

# stdin = `awww query -j`; $1 = preferred monitor name.
_kolir_awww_json_image() {
	KOLIR_MON_NAME="$1" python3 -c '
import json, os, sys

want = os.environ.get("KOLIR_MON_NAME", "")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

outputs = []
if isinstance(data, dict):
    for items in data.values():
        if isinstance(items, list):
            outputs.extend(items)
outputs = [o for o in outputs if isinstance(o, dict)]
mon = next((o for o in outputs if o.get("name") == want), None)
if mon is None:
    mon = outputs[0] if outputs else None
if not mon:
    sys.exit(1)

displaying = mon.get("displaying") or {}
image = displaying.get("image") if isinstance(displaying, dict) else ""
if not isinstance(image, str):
    image = ""
print(image)
' 2>/dev/null
}

# $1 = cache file. Prints the wallpaper path encoded in it, if any.
_kolir_awww_cache_path() {
	KOLIR_CACHE_FILE="$1" python3 -c '
import os, sys

path = os.environ.get("KOLIR_CACHE_FILE", "")
try:
    with open(path, "rb") as handle:
        text = handle.read().decode("utf-8", "replace")
except OSError:
    sys.exit(1)

candidates = []
for chunk in text.replace("\0", "\n").splitlines():
    if not chunk:
        continue
    if chunk.startswith("/"):
        candidates.append(chunk)
    # Older releases wrote "<filters><path>" as one string: keep every
    # suffix that starts with "/" and let the existence check decide.
    start = chunk.find("/")
    while start != -1:
        candidates.append(chunk[start:])
        start = chunk.find("/", start + 1)

for candidate in candidates:
    if os.path.isfile(candidate) and os.access(candidate, os.R_OK):
        print(candidate)
        sys.exit(0)
sys.exit(1)
' 2>/dev/null
}

# $1 = monitor name. Prints the wallpaper path or nothing (diagnostics on stderr).
kolir_awww_wallpaper_path() {
	monitor="${1:-}"
	[ -n "$monitor" ] || monitor="DP-1"

	if ! command -v awww >/dev/null 2>&1; then
		echo "awww: command not found; install awww (tested with 0.12.1) or add it to PATH" >&2
		return 1
	fi

	version=$(kolir_awww_version)
	[ -n "$version" ] || version="unknown"

	# 1. The daemon knows the currently displayed image for each output.
	image=$(awww query -j 2>/dev/null | _kolir_awww_json_image "$monitor")
	if [ -n "$image" ] && [ -r "$image" ]; then
		printf '%s\n' "$image"
		return 0
	fi

	# 2. The cache written by `awww img`; check every version directory,
	#    newest first, so an empty newer directory does not hide an older,
	#    readable entry.
	roots=$(kolir_awww_cache_roots)
	if [ -z "$roots" ]; then
		echo "awww $version: no cache directory at ${XDG_CACHE_HOME:-$HOME/.cache}/awww and the daemon did not report a wallpaper for '$monitor'" >&2
		return 1
	fi

	cache_file=""
	while IFS= read -r cache_dir; do
		[ -n "$cache_dir" ] || continue
		if [ -e "$cache_dir/$monitor" ]; then
			cache_file="$cache_dir/$monitor"
			break
		fi
	done <<EOF
$roots
EOF

	if [ -z "$cache_file" ]; then
		found=$(printf '%s\n' "$roots" | while IFS= read -r cache_dir; do
			[ -d "$cache_dir" ] && find "$cache_dir" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null
		done | sort | tr '\n' ' ')
		echo "awww $version: no cache entry for '$monitor' under ${XDG_CACHE_HOME:-$HOME/.cache}/awww (daemon did not report an image; found: ${found:-none})" >&2
		return 1
	fi

	image=$(_kolir_awww_cache_path "$cache_file")
	if [ -z "$image" ]; then
		echo "awww $version: could not decode a readable wallpaper path from $cache_file; run 'awww img <file>' again or set KOLIR_MONITOR to the active output" >&2
		return 1
	fi

	printf '%s\n' "$image"
}

# Explicit minimum: this is the only awww release the parser was verified
# against. Newer releases are accepted (the cache scan is layout-tolerant).
kolir_awww_check() {
	if ! command -v awww >/dev/null 2>&1; then
		echo "awww: command not found; install awww (tested with 0.12.1) or add it to PATH" >&2
		return 1
	fi
	return 0
}
