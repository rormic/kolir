#!/usr/bin/env zsh
# The awww cache is NUL-separated: `crop:center\0Lanczos3\0/wallpaper.png`
# (older awww versions wrote `...Lanczos3/wallpaper.png` in one piece).
# Normalize NULs to newlines, strip everything up to and including the
# Lanczos3 filter spec, and take the last resulting line as the path.
IMAGE_PATH=$(tr '\0' '\n' < ~/.cache/awww/0.12.1/DP-1 | sed -E 's/^.*Lanczos3//' | tail -n 1)
if [[ ! -r "$IMAGE_PATH" ]]; then
    echo "generate-colors.sh: cannot read wallpaper path '${IMAGE_PATH}' extracted from ~/.cache/awww/0.12.1/DP-1" >&2
    exit 1
fi

# hyprlock reads a pre-blurred, vignetted wallpaper so the lock starts fast
# and the edges stay darker than the center.
LOCK_BACKGROUND="$HOME/.cache/kolir/lock-background.png"
mkdir -p "$(dirname "$LOCK_BACKGROUND")"
if command -v ffmpeg >/dev/null 2>&1; then
    read -r MON_W MON_H <<< "$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys
ms=json.load(sys.stdin)
m=next((x for x in ms if x.get("name")=="DP-1"), ms[0] if ms else None)
print(m["width"], m["height"]) if m else None' 2>/dev/null)"
    MON_W=${MON_W:-2560}
    MON_H=${MON_H:-1440}
    ffmpeg -y -loglevel error -i "$IMAGE_PATH" \
        -vf "scale=${MON_W}:${MON_H}:force_original_aspect_ratio=increase,crop=${MON_W}:${MON_H},gblur=sigma=28,eq=brightness=0.03:saturation=1.0,vignette=PI/5" \
        -frames:v 1 "$LOCK_BACKGROUND"

    # 25% black in the centre, fading to transparent at a 600 px radius
    LOCK_GLOW="$HOME/.cache/kolir/lock-glow.png"
    ffmpeg -y -loglevel error -f lavfi -i "color=c=black:s=1200x1200,format=rgba" \
        -vf "geq=r=0:g=0:b=0:a='255*0.25*max(0,1-(pow(X-W/2,2)+pow(Y-H/2,2))/pow(W/2,2))'" \
        -frames:v 1 "$LOCK_GLOW"
fi

CURRENT_THEME=$(<"$HOME/.cache/current_theme")

matugen image "$IMAGE_PATH" --source-color-index 0 -m "$CURRENT_THEME" -t scheme-neutral

# The lock screen always uses a dark palette so white typography stays
# readable over the blurred wallpaper, even when the desktop theme is light.
matugen image "$IMAGE_PATH" --source-color-index 0 -m dark -t scheme-neutral \
    -c "$HOME/.config/matugen/hyprlock.toml"
