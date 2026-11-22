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

# Write the resolved light/dark state. ThemeToggle watches this file, so the
# bar icon follows the generated palette immediately.
kolir_write_theme_state() {
	_kolir_state=$(kolir_theme_state_file)
	mkdir -p -- "${_kolir_state%/*}" 2>/dev/null || return 1
	printf '%s\n' "$1" >"$_kolir_state"
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
}

# Apply an explicit light/dark mode: the state file first (the bar icon follows
# it), then the system theme names.
kolir_apply_theme_mode() {
	kolir_write_theme_state "$1" || return 1
	kolir_apply_system_theme "$1"
}

# Keep the persisted Appearance mode in sync when the bar toggle flips the
# theme. AppearanceService owns the file as one-line JSON with exactly "type",
# "contrast" and "mode"; a missing file means the Appearance page was never
# used, so the legacy current_theme path still applies.
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
