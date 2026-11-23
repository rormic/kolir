#!/usr/bin/env zsh
# Regenerates every Matugen-derived palette (Foot, live terminals, Neovim,
# Hyprland, Quickshell, GTK) and the always-dark lock-screen palette.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# config/hypr/scripts -> repository root; readlink resolves the
# ~/.config/hypr/scripts symlink used by the installed desktop.
REPO_ROOT=$(readlink -f -- "$SCRIPT_DIR/../../..")
. "$SCRIPT_DIR/lib/monitors.sh"
. "$SCRIPT_DIR/lib/awww.sh"
. "$SCRIPT_DIR/lib/mpvpaper.sh"
. "$SCRIPT_DIR/lib/wallpaper.sh"
. "$SCRIPT_DIR/lib/theme.sh"

warn() {
    printf 'generate-colors.sh: %s\n' "$*" >&2
}

# --- Config selection -------------------------------------------------------
# $KOLIR_MATUGEN_CONFIG wins, then the installed config, then the repository
# copy so a fresh checkout works before kolir setup has linked anything.
if [[ -n ${KOLIR_MATUGEN_CONFIG:-} ]]; then
    MAIN_CONFIG=$KOLIR_MATUGEN_CONFIG
elif [[ -r "$HOME/.config/matugen/config.toml" ]]; then
    MAIN_CONFIG=$HOME/.config/matugen/config.toml
else
    MAIN_CONFIG=$REPO_ROOT/config/matugen/config.toml
fi

if [[ ! -r $MAIN_CONFIG ]]; then
    warn "Matugen config '${MAIN_CONFIG}' is not readable; set KOLIR_MATUGEN_CONFIG to an existing config file"
    exit 1
fi
MAIN_CONFIG=$(readlink -f -- "$MAIN_CONFIG") || exit 1

LOCK_CONFIG=$HOME/.config/matugen/hyprlock.toml

if ! command -v matugen >/dev/null 2>&1; then
    warn "matugen was not found; install matugen and rerun"
    exit 1
fi

# --- Wallpaper --------------------------------------------------------------
# The monitor is chosen at runtime: $KOLIR_MONITOR, then the focused monitor,
# then the first one, then DP-1 (the author's output).
MONITOR=$(kolir_monitor_name)

# The active wallpaper comes from lib/wallpaper.sh: a live mpvpaper video when
# the video backend is really playing, otherwise awww's image (queried from the
# daemon first, then decoded from its version-tolerant cache). A video is
# sampled into a cached frame so Matugen and the lock background keep working.
if ! IMAGE_PATH=$(kolir_wallpaper_image "$MONITOR"); then
    warn "no readable wallpaper for monitor '$MONITOR'; set one with SUPER+CTRL+T and rerun"
    exit 1
fi
if [[ -z $IMAGE_PATH || ! -r $IMAGE_PATH ]]; then
    warn "the wallpaper resolver returned '${IMAGE_PATH:-<empty>}' for monitor '$MONITOR', which is not readable; set a wallpaper again (SUPER+CTRL+T)"
    exit 1
fi

# --- Theme state ------------------------------------------------------------
THEME_FILE=$HOME/.cache/current_theme
CURRENT_THEME=""
if [[ -f $THEME_FILE ]]; then
    CURRENT_THEME=$(tr -d '[:space:]' < "$THEME_FILE" 2>/dev/null)
fi

case $CURRENT_THEME in
    light | dark) ;;
    *)
        if [[ -e $THEME_FILE ]]; then
            warn "ignoring invalid theme '${CURRENT_THEME:-<empty>}' in $THEME_FILE; using dark"
        else
            if mkdir -p -- "${THEME_FILE%/*}" && printf 'dark\n' > "$THEME_FILE"; then
                warn "theme state $THEME_FILE was missing; created it with 'dark'"
            else
                warn "theme state $THEME_FILE is missing and could not be created; using dark for this run"
            fi
        fi
        CURRENT_THEME=dark
        ;;
esac

# --- Appearance settings ----------------------------------------------------
# The Appearance settings page owns ~/.cache/quickshell/appearance.json:
#   {"type":"scheme-neutral","contrast":0,"mode":"auto","crossfade":true}
# `mode` is the user intent (auto/light/dark). Auto follows the sunrise/sunset
# schedule in AppearanceService, which passes the resolved light/dark; light
# and dark are explicit and also update the resolved current_theme. Environment
# variables win so a caller can regenerate without writing the state file.
# `crossfade` is read only by the shell (Colors.qml) and is ignored here.
APPEARANCE_FILE=$HOME/.cache/quickshell/appearance.json

appearance_string() {
    [[ -r $APPEARANCE_FILE ]] || return 0
    sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$APPEARANCE_FILE" 2>/dev/null | head -n 1
}

appearance_number() {
    [[ -r $APPEARANCE_FILE ]] || return 0
    sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([-0-9.]\+\).*/\1/p' \
        "$APPEARANCE_FILE" 2>/dev/null | head -n 1
}

SCHEME_TYPE=${KOLIR_MATUGEN_TYPE:-}
[[ -n $SCHEME_TYPE ]] || SCHEME_TYPE=$(appearance_string type)
# An empty value means "unset"; contrast 0 is a real value, not a fallback.
if [[ -z ${KOLIR_MATUGEN_CONTRAST+x} ]]; then
    CONTRAST=$(appearance_number contrast)
else
    CONTRAST=$KOLIR_MATUGEN_CONTRAST
fi
MODE_INTENT=${KOLIR_MATUGEN_MODE:-}
[[ -n $MODE_INTENT ]] || MODE_INTENT=$(appearance_string mode)

case $SCHEME_TYPE in
    scheme-content | scheme-expressive | scheme-fidelity | scheme-fruit-salad \
        | scheme-monochrome | scheme-neutral | scheme-rainbow \
        | scheme-tonal-spot | scheme-vibrant | scheme-smart) ;;
    "")
        SCHEME_TYPE=scheme-neutral
        ;;
    *)
        warn "ignoring unknown scheme type '$SCHEME_TYPE'; using scheme-neutral"
        SCHEME_TYPE=scheme-neutral
        ;;
esac

if [[ -n $CONTRAST ]] \
    && ! awk -v c="$CONTRAST" 'BEGIN {
        exit !(c ~ /^-?[0-9]+([.][0-9]+)?$/ && c >= -1 && c <= 1)
    }'; then
    warn "ignoring contrast '$CONTRAST' (expected -1..1); using 0"
    CONTRAST=0
fi
CONTRAST=${CONTRAST:-0}

case $MODE_INTENT in
    auto | light | dark) ;;
    "")
        MODE_INTENT=$CURRENT_THEME
        ;;
    *)
        warn "ignoring unknown mode '$MODE_INTENT'; using '$CURRENT_THEME'"
        MODE_INTENT=$CURRENT_THEME
        ;;
esac

if [[ $MODE_INTENT == auto ]]; then
    # AppearanceService owns the sunrise/sunset schedule and passes the
    # resolved light/dark in KOLIR_MATUGEN_MODE. A bare auto (for example from
    # a wallpaper change while the shell is down) keeps the last resolved
    # theme instead of letting matugen choose from the image.
    MATUGEN_MODE=$CURRENT_THEME
    kolir_apply_system_theme "$CURRENT_THEME"
else
    MATUGEN_MODE=$MODE_INTENT
    # An explicit mode is authoritative: keep the bar icon, GTK and KDE in
    # sync with the palette that is about to be generated.
    if [[ $CURRENT_THEME != $MODE_INTENT ]]; then
        if kolir_apply_theme_mode "$MODE_INTENT"; then
            CURRENT_THEME=$MODE_INTENT
        else
            warn "could not write the theme state for '$MODE_INTENT'"
        fi
    fi
fi

# --- Template pre-validation ------------------------------------------------
# Print "<template>\t<resolved input path>" for every template whose input is
# not a readable file. Exit 0 = all present, 1 = entries printed, 3 = the
# config could not be parsed (fall back to matugen's own diagnostics).
matugen_missing_inputs() {
    KOLIR_MATUGEN_CONFIG_FILE=$1 python3 - <<'PY'
import os
import sys
import tomllib

config = os.environ["KOLIR_MATUGEN_CONFIG_FILE"]
try:
    with open(config, "rb") as handle:
        data = tomllib.load(handle)
except Exception as error:
    print(error, file=sys.stderr)
    sys.exit(3)

base = os.path.dirname(os.path.abspath(config))
templates = data.get("templates", {})
missing = []
if isinstance(templates, dict):
    for name, template in templates.items():
        if not isinstance(template, dict):
            continue
        value = template.get("input_path")
        if not isinstance(value, str) or not value.strip():
            continue
        path = os.path.expanduser(value)
        if not os.path.isabs(path):
            path = os.path.join(base, path)
        path = os.path.normpath(path)
        if not os.path.isfile(path) or not os.access(path, os.R_OK):
            missing.append((str(name), path))

for name, path in missing:
    print(f"{name}\t{path}")
sys.exit(1 if missing else 0)
PY
}

print_missing_inputs() {
    local name path
    while IFS=$'\t' read -r name path; do
        [[ -n $name ]] || continue
        printf '    %s: %s\n' "$name" "$path" >&2
    done <<< "$1"
}

VALIDATE_INPUTS=false
if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
    VALIDATE_INPUTS=true
else
    warn "python3 with tomllib is unavailable; skipping Matugen template pre-validation"
fi

# The main config must not produce partial output: check every input first.
if [[ $VALIDATE_INPUTS == true ]]; then
    MISSING_INPUTS=$(matugen_missing_inputs "$MAIN_CONFIG")
    case $? in
        0) ;;
        1)
            warn "missing template input(s) in $MAIN_CONFIG; no colors were generated:"
            print_missing_inputs "$MISSING_INPUTS"
            warn "restore the missing template(s) and rerun"
            exit 1
            ;;
        *)
            warn "could not parse $MAIN_CONFIG with tomllib; letting matugen validate it"
            ;;
    esac
fi

# The lock palette is optional: a broken lock config must not block desktop
# colors.
LOCK_READY=false
if [[ ! -r $LOCK_CONFIG ]]; then
    warn "lock palette skipped: '$LOCK_CONFIG' is missing or unreadable"
elif [[ $VALIDATE_INPUTS == true ]]; then
    MISSING_INPUTS=$(matugen_missing_inputs "$LOCK_CONFIG")
    case $? in
        0) LOCK_READY=true ;;
        1)
            warn "lock palette skipped: missing template input(s) in $LOCK_CONFIG:"
            print_missing_inputs "$MISSING_INPUTS"
            ;;
        *)
            warn "could not parse $LOCK_CONFIG with tomllib; letting matugen validate it"
            LOCK_READY=true
            ;;
    esac
else
    LOCK_READY=true
fi

# --- Hyprland availability --------------------------------------------------
# The hyprland template's post_hook runs `hyprctl reload`. When there is no
# live instance, shadow hyprctl only for matugen so the hook becomes a no-op
# instead of failing on every refresh.
HYPRCTL_STUB_DIR=""
cleanup() {
    [[ -n $HYPRCTL_STUB_DIR ]] && rm -rf -- "$HYPRCTL_STUB_DIR"
}
trap cleanup EXIT

HYPRLAND_AVAILABLE=false
if ! command -v hyprctl >/dev/null 2>&1; then
    warn "hyprctl was not found; skipping the hyprctl reload post-hook"
elif ! hyprctl -j monitors >/dev/null 2>&1; then
    warn "no Hyprland instance is available; skipping the hyprctl reload post-hook"
else
    HYPRLAND_AVAILABLE=true
fi

if [[ $HYPRLAND_AVAILABLE == false ]]; then
    if HYPRCTL_STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kolir-matugen.XXXXXX"); then
        printf '#!/bin/sh\nexit 0\n' > "$HYPRCTL_STUB_DIR/hyprctl"
        chmod +x "$HYPRCTL_STUB_DIR/hyprctl"
    else
        HYPRCTL_STUB_DIR=""
        warn "could not create a temporary hyprctl shim; the reload post-hook may fail"
    fi
fi

run_matugen() {
    if [[ -n $HYPRCTL_STUB_DIR ]]; then
        PATH="$HYPRCTL_STUB_DIR:$PATH" command matugen "$@"
    else
        command matugen "$@"
    fi
}

# --- Lock background --------------------------------------------------------
# hyprlock reads a pre-blurred, vignetted wallpaper so the lock starts fast
# and the edges stay darker than the center.
LOCK_BACKGROUND=$HOME/.cache/kolir/lock-background.png
if command -v ffmpeg >/dev/null 2>&1; then
    if ! mkdir -p -- "${LOCK_BACKGROUND%/*}"; then
        warn "could not create ${LOCK_BACKGROUND%/*}; skipping the lock-screen background"
    else
        GEOMETRY=$(kolir_monitor_geometry)
        MON_W=""
        MON_H=""
        # kolir_monitor_geometry prints "x,y WxH"; take the size field only.
        if [[ $GEOMETRY == *" "* ]]; then
            SIZE=${GEOMETRY##* }
            MON_W=${SIZE%x*}
            MON_H=${SIZE#*x}
        fi
        MON_W=${MON_W:-2560}
        MON_H=${MON_H:-1440}
        if ! ffmpeg -y -loglevel error -i "$IMAGE_PATH" \
            -vf "scale=${MON_W}:${MON_H}:force_original_aspect_ratio=increase,crop=${MON_W}:${MON_H},gblur=sigma=28,eq=brightness=0.03:saturation=1.0,vignette=PI/5" \
            -frames:v 1 "$LOCK_BACKGROUND"; then
            warn "ffmpeg could not generate $LOCK_BACKGROUND; continuing without it"
        fi

        # 25% black in the centre, fading to transparent at a 600 px radius
        LOCK_GLOW="$HOME/.cache/kolir/lock-glow.png"
        if ! ffmpeg -y -loglevel error -f lavfi -i "color=c=black:s=1200x1200,format=rgba" \
            -vf "geq=r=0:g=0:b=0:a='255*0.25*max(0,1-(pow(X-W/2,2)+pow(Y-H/2,2))/pow(W/2,2))'" \
            -frames:v 1 "$LOCK_GLOW"; then
            warn "ffmpeg could not generate $LOCK_GLOW; continuing without it"
        fi
    fi
else
    warn "ffmpeg was not found; skipping the lock-screen background and glow images"
fi

# --- Generation -------------------------------------------------------------
if ! run_matugen image "$IMAGE_PATH" --source-color-index 0 \
    --mode "$MATUGEN_MODE" --type "$SCHEME_TYPE" --contrast "$CONTRAST" \
    -c "$MAIN_CONFIG"; then
    warn "matugen failed while generating the desktop palette from '$IMAGE_PATH' with $MAIN_CONFIG"
    exit 1
fi

# The lock screen always uses a dark palette so white typography stays
# readable over the blurred wallpaper, even when the desktop theme is light.
# It follows the selected scheme type and contrast so the lock palette belongs
# to the same family. The lock palette is optional: a failed lock run must not
# turn an otherwise successful wallpaper/theme change into a reported failure.
if [[ $LOCK_READY == true ]]; then
    if ! run_matugen image "$IMAGE_PATH" --source-color-index 0 \
        --mode dark --type "$SCHEME_TYPE" --contrast "$CONTRAST" \
        -c "$LOCK_CONFIG"; then
        warn "matugen failed while generating the lock palette from '$IMAGE_PATH' with $LOCK_CONFIG; desktop colors were generated, continuing"
    fi
fi
