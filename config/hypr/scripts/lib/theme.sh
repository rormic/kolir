#!/bin/sh
# Shared light/dark theme application for the kolir helpers.
#
# `~/.cache/current_theme` is the resolved desktop mode (light or dark). The
# Appearance settings page stores a separate user intent (auto, light, dark) in
# ~/.cache/quickshell/appearance.json; "auto" is resolved by matugen's smart
# mode, while the explicit modes land in the state file below.
#
# Sourced by generate-colors.sh (zsh) and toggle-theme.sh (bash), so keep this
# file POSIX sh.

kolir_theme_state_file() {
	printf '%s\n' "${HOME}/.cache/current_theme"
}

# Write the resolved light/dark state. AppearanceService and the theme toggle
# read this file, so the palette follows the generated state immediately.
kolir_write_theme_state() {
	_kolir_state=$(kolir_theme_state_file)
	mkdir -p -- "${_kolir_state%/*}" 2>/dev/null || return 1
	printf '%s\n' "$1" >"$_kolir_state"
}

# ── Cursor variant ─────────────────────────────────────────────────────────
# The cursor theme is machine-specific: user.lua sets XCURSOR_THEME (for
# example Mocu-White-Left). The Appearance switch pairs it with the palette by
# swapping only the light/dark token of that name, so a theme without such a
# token (Adwaita, Bibata-…) is left alone instead of being replaced.

# Cache of the variant this session applied last. generate-colors.sh runs on
# every wallpaper and slider change; without it each run would reload an
# unchanged cursor. apply-cursor.sh passes --force after a compositor restart,
# where the live cursor is back to the env value.
kolir_cursor_state_file() {
	printf '%s\n' "${HOME}/.cache/kolir/cursor-theme"
}

# True while the Appearance page's "Cursor follows theme" switch is on. The
# state file is one-line JSON owned by AppearanceService.
kolir_cursor_follows_theme() {
	_kolir_appearance="${HOME}/.cache/quickshell/appearance.json"
	[ -r "$_kolir_appearance" ] || return 1
	grep -q '"cursor"[[:space:]]*:[[:space:]]*true' "$_kolir_appearance" 2>/dev/null
}

kolir_cursor_theme_exists() {
	_kolir_candidate=$1
	_kolir_paths=${XCURSOR_PATH:-"$HOME/.icons:$HOME/.local/share/icons:/usr/share/icons"}
	_kolir_old_ifs=$IFS
	IFS=:
	# shellcheck disable=SC2086 # intentional split of the colon list
	set -- $_kolir_paths
	IFS=$_kolir_old_ifs

	for _kolir_dir in "$@"; do
		[ -n "$_kolir_dir" ] || continue
		[ -d "$_kolir_dir/$_kolir_candidate" ] && return 0
	done
	return 1
}

# Print the cursor theme matching light/dark, or nothing when the machine's
# theme has no such variant. KOLIR_CURSOR_THEME overrides the detected base
# name (tests, and machines whose cursor theme is not set in user.lua).
kolir_cursor_theme() {
	case $1 in
		light | dark) ;;
		*) return 0 ;;
	esac

	_kolir_base=${KOLIR_CURSOR_THEME:-${XCURSOR_THEME:-}}
	if [ -z "$_kolir_base" ] && command -v gsettings >/dev/null 2>&1; then
		_kolir_base=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
	fi
	[ -n "$_kolir_base" ] || return 0

	_kolir_dark=$(printf '%s\n' "$_kolir_base" \
		| sed -e 's/White/Black/' -e 's/Light/Dark/')
	_kolir_light=$(printf '%s\n' "$_kolir_base" \
		| sed -e 's/Black/White/' -e 's/Dark/Light/')

	if [ "$1" = "dark" ]; then
		_kolir_variant=$_kolir_dark
		_kolir_other=$_kolir_light
	else
		_kolir_variant=$_kolir_light
		_kolir_other=$_kolir_dark
	fi

	# A theme has a pair when either swapped name differs from the base and is
	# installed. The requested variant is returned even when it equals the base
	# (the live cursor may currently be the other one), and nothing is printed
	# for a single-variant theme such as Adwaita.
	if [ "$_kolir_variant" != "$_kolir_base" ] \
		&& kolir_cursor_theme_exists "$_kolir_variant"; then
		printf '%s\n' "$_kolir_variant"
		return 0
	fi
	if [ "$_kolir_other" != "$_kolir_base" ] \
		&& kolir_cursor_theme_exists "$_kolir_other"; then
		printf '%s\n' "$_kolir_variant"
	fi
	return 0
}

# Apply the light/dark cursor variant to GTK, KDE and the live Hyprland
# cursor. The second argument is "force" to skip the applied-variant cache.
kolir_apply_cursor_theme() {
	_kolir_mode=$1
	_kolir_force=${2:-false}
	_kolir_cursor=$(kolir_cursor_theme "$_kolir_mode")
	[ -n "$_kolir_cursor" ] || return 0

	_kolir_cursor_state=$(kolir_cursor_state_file)
	_kolir_applied=""
	[ -r "$_kolir_cursor_state" ] \
		&& _kolir_applied=$(cat "$_kolir_cursor_state" 2>/dev/null)
	if [ "$_kolir_force" != "true" ] && [ "$_kolir_applied" = "$_kolir_cursor" ]; then
		return 0
	fi

	_kolir_cursor_size=${KOLIR_CURSOR_SIZE:-${XCURSOR_SIZE:-24}}
	case $_kolir_cursor_size in
		'' | *[!0-9]*) _kolir_cursor_size=24 ;;
	esac

	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface cursor-theme \
			"$_kolir_cursor" >/dev/null 2>&1 || true
	fi

	if command -v kwriteconfig6 >/dev/null 2>&1; then
		kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme \
			"$_kolir_cursor" >/dev/null 2>&1 || true
	fi

	# Hyprland owns the compositor cursor; setcursor switches it live, so the
	# pointer follows the palette without a compositor restart.
	if command -v hyprctl >/dev/null 2>&1; then
		hyprctl setcursor "$_kolir_cursor" "$_kolir_cursor_size" >/dev/null 2>&1 || true
	fi

	mkdir -p -- "${_kolir_cursor_state%/*}" 2>/dev/null \
		&& printf '%s\n' "$_kolir_cursor" >"$_kolir_cursor_state"
}

# Apply the matching GTK and KDE theme names. Missing tools are skipped so a
# machine without gsettings/kwriteconfig6 still gets the generated colors.
kolir_apply_system_theme() {
	if [ "$1" = "dark" ]; then
		_kolir_gtk_theme=Adwaita-dark
		_kolir_kde_scheme=BreezeDark
	else
		_kolir_gtk_theme=Adwaita
		_kolir_kde_scheme=BreezeLight
	fi

	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface color-scheme "prefer-$1" >/dev/null 2>&1 || true
		gsettings set org.gnome.desktop.interface gtk-theme "$_kolir_gtk_theme" >/dev/null 2>&1 || true
	fi

	if command -v kwriteconfig6 >/dev/null 2>&1; then
		kwriteconfig6 --file kdeglobals --group General --key ColorScheme \
			"$_kolir_kde_scheme" >/dev/null 2>&1 || true
	fi

	if kolir_cursor_follows_theme; then
		kolir_apply_cursor_theme "$1"
	fi
}

# Apply an explicit light/dark mode: the state file first (the bar icon follows
# it), then the system theme names.
kolir_apply_theme_mode() {
	kolir_write_theme_state "$1" || return 1
	kolir_apply_system_theme "$1"
}

# Keep the persisted Appearance mode in sync when the bar toggle flips the
# theme. AppearanceService owns the file as one-line JSON; this helper rewrites
# only "mode" and leaves the other keys (type, contrast, crossfade) alone. A
# missing file means the Appearance page was never used, so the legacy
# current_theme path still applies.
kolir_sync_appearance_mode() {
	_kolir_appearance="${HOME}/.cache/quickshell/appearance.json"
	[ -r "$_kolir_appearance" ] || return 0

	_kolir_tmp="${_kolir_appearance}.tmp.$$"
	if sed 's/"mode"[[:space:]]*:[[:space:]]*"[^"]*"/"mode":"'"$1"'"/' \
		"$_kolir_appearance" >"$_kolir_tmp" 2>/dev/null; then
		mv -- "$_kolir_tmp" "$_kolir_appearance"
	else
		rm -f -- "$_kolir_tmp"
		return 1
	fi
}
