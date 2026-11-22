#!/bin/sh
# Emits the pango markup for hyprlock's mixed-style clock: one glyph span per
# character, mixing width (stretch), weight, slant, colour and scale of Google
# Sans Flex. Colours come from ~/.config/hypr/hyprlock-colors.conf; sensible
# fallbacks keep the clock usable before the first Matugen run.
#
# The style mask is positional, so it stays stable as the digits change.
# `base` must equal the label's font_size in hyprlock.conf; span sizes are
# absolute pango units (base * 767 == the label size, calibrated).
set -eu

COLORS=${KOLIR_HYPRLOCK_COLORS:-${HOME}/.config/hypr/hyprlock-colors.conf}
TIME=${1:-$(date +%H:%M)}
BASE=210

awk -v time="$TIME" -v colorsFile="$COLORS" -v base="$BASE" '
function hexcol(value,   at) {
    if (match(value, /[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/))
        return "#" substr(value, RSTART, 6)
    return value
}
BEGIN {
    on       = "#e4e2e3"
    date     = "#e4e2e3"
    primary  = "#a4c9fe"
    tertiary = "#bcc7db"
    err      = "#ffb4ab"

    while ((getline line < colorsFile) > 0) {
        sub(/#.*/, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "" || index(line, "=") == 0)
            continue
        key = line
        sub(/=.*/, "", key)
        sub(/^\$/, "", key)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        val = line
        sub(/^[^=]*=/, "", val)
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == "onSurface")        on = val
        else if (key == "dateText")    date = val
        else if (key == "primary")     primary = val
        else if (key == "tertiary")    tertiary = val
        else if (key == "error")       err = val
    }
    close(colorsFile)

    on = hexcol(on); date = hexcol(date); primary = hexcol(primary)
    tertiary = hexcol(tertiary); err = hexcol(err)

    fam[0]     = "Google Sans Flex"
    stretch[0] = "condensed";      weight[0] = 900; ital[0] = 0
    color[0]   = on;              ls[0] = 2048;    sizef[0] = 1.00

    fam[1]     = "Google Sans Flex"
    stretch[1] = "normal";         weight[1] = 400; ital[1] = 1
    color[1]   = date;             ls[1] = 2048;    sizef[1] = 0.98

    fam[2]     = "Google Sans Flex"
    stretch[2] = "normal";         weight[2] = 500; ital[2] = 0
    color[2]   = primary;          ls[2] = 0;       sizef[2] = 0.60

    # rounded terminals (the ROND instance installed as ... Round)
    fam[3]     = "Google Sans Flex Round"
    stretch[3] = "expanded";       weight[3] = 800; ital[3] = 0
    color[3]   = on;               ls[3] = 2048;    sizef[3] = 1.02

    fam[4]     = "Google Sans Flex"
    stretch[4] = "ultracondensed"; weight[4] = 800; ital[4] = 1
    color[4]   = primary;          ls[4] = 2048;    sizef[4] = 1.00

    base_span = base * 767
    # Spaces on both edges: hyprgraphics renders into a surface sized from
    # the logical extents of the layout, so an italic overhang past that box
    # would be clipped. Symmetric padding absorbs it and keeps the line
    # centred.
    printf "<span> </span>"
    for (i = 1; i <= length(time); i++) {
        idx = i - 1
        attrs = sprintf("font_family=\"%s\" stretch=\"%s\" weight=\"%d\" foreground=\"%s\"",
                        fam[idx], stretch[idx], weight[idx], color[idx])
        if (ital[idx])
            attrs = attrs " style=\"italic\""
        if (ls[idx] != 0)
            attrs = attrs sprintf(" letter_spacing=\"%d\"", ls[idx])
        if (sizef[idx] != 1.0)
            attrs = attrs sprintf(" size=\"%d\"", int(base_span * sizef[idx]))
        printf "<span %s>%s</span>", attrs, substr(time, i, 1)
    }
    printf "<span> </span>"
}'
