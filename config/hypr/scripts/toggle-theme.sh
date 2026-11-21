#!/usr/bin/env bash
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_FILE="$HOME/.cache/current_theme"

current=$(cat "$STATE_FILE" 2>/dev/null)
[[ "$current" == "light" ]] && new="dark" || new="light"

if [[ "$new" == "dark" ]]; then
    gtk_theme="Adwaita-dark"
    kde_scheme="BreezeDark"
else
    gtk_theme="Adwaita"
    kde_scheme="BreezeLight"
fi

# GTK3 + GTK4/libadwaita
gsettings set org.gnome.desktop.interface color-scheme "prefer-$new"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"

# KDE
kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$kde_scheme"

mkdir -p "$(dirname "$STATE_FILE")"
echo "$new" > "$STATE_FILE"

zsh "$SCRIPT_DIR/generate-colors.sh"
