# AGENTS.md — Desktop Environment Reference

## 1. Overview
`kolir` is an Arch Linux desktop configuration managing a Wayland environment powered by Hyprland (configured via Lua) and a custom desktop shell written in Quickshell (QML). It features an automated Material Design 3 dynamic theming pipeline driven by Matugen, extracting color schemes from wallpapers to style Hyprland, Foot terminal, GTK/KDE, and Quickshell reactively. Machine-specific configurations are decoupled from shared repository settings via loaders and user override files.

## 2. Directory Map
- [config/hypr/hyprland.lua](file:///home/sakura/.local/share/kolir/config/hypr/hyprland.lua): Shared Hyprland config (Lua bindings `hl.*`, window/layer rules, keybinds; loads colors and `user.lua`).
- [config/hypr/user.lua.example](file:///home/sakura/.local/share/kolir/config/hypr/user.lua.example): Template for untracked machine-specific settings (`~/.config/hypr/user.lua`: monitors, autostart, personal binds).
- [config/hypr/hyprsunset.conf](file:///home/sakura/.local/share/kolir/config/hypr/hyprsunset.conf): Blue-light filter configuration.
- [config/hypr/scripts/](file:///home/sakura/.local/share/kolir/config/hypr/scripts): Helper scripts (`generate_colors.sh`, `set_wallpaper.sh`, `toggle-theme.sh`, `brightness.sh`, `screen-record.sh`).
- [config/quickshell/shell.qml](file:///home/sakura/.local/share/kolir/config/quickshell/shell.qml): Quickshell root (`ShellRoot`), instantiating bar, launcher, notifications, OSDs, recorder setup, and corner masks.
- [config/quickshell/bar/](file:///home/sakura/.local/share/kolir/config/quickshell/bar): Top panel (`Bar.qml`) and widgets. When working on the bar, read [docs/bar.md](file:///home/sakura/.local/share/kolir/docs/bar.md).
- [config/quickshell/theme/](file:///home/sakura/.local/share/kolir/config/quickshell/theme): Singletons declared in `qmldir` (`Colors`, `Dimensions`, `Typography`, `Icons`, `AudioService`, `BrightnessService`).
- [config/quickshell/launcher/](file:///home/sakura/.local/share/kolir/config/quickshell/launcher): App launcher, runner, and cliphist clipboard browser (`Launcher.qml`, Python helpers).
- [config/quickshell/settings/](file:///home/sakura/.local/share/kolir/config/quickshell/settings): Dropdown quick-settings panel (`SettingsMenu.qml`) with network and bluetooth pages.
- [config/quickshell/notification/](file:///home/sakura/.local/share/kolir/config/quickshell/notification): Wayland notification overlay daemon (`Notification.qml`).
- [config/quickshell/osd/](file:///home/sakura/.local/share/kolir/config/quickshell/osd): On-screen display popups for volume and brightness (`VolumeOsd.qml`, `BrightnessOsd.qml`).
- [config/quickshell/rec/](file:///home/sakura/.local/share/kolir/config/quickshell/rec): Modal for one-shot screen recording settings (`RecordingSetup.qml`).
- [config/quickshell/corners/](file:///home/sakura/.local/share/kolir/config/quickshell/corners): Screen-corner rounding mask overlay (`Corner.qml`).
- [config/matugen/config.toml](file:///home/sakura/.local/share/kolir/config/matugen/config.toml): Matugen mapping of templates to output configuration paths and reload post-hooks.
- [config/matugen/templates/](file:///home/sakura/.local/share/kolir/config/matugen/templates): Color templates for `foot-colors.ini`, `hyprland-colors.lua`, `nvim-colors.lua`, and `terminal-sequences`.
- [config/foot/](file:///home/sakura/.local/share/kolir/config/foot): Foot terminal base config (`foot.ini`) and generated colors (`colors.ini`).
- [config/mpv/mpv.conf](file:///home/sakura/.local/share/kolir/config/mpv/mpv.conf): MPV media player configuration.
- [install.sh](file:///home/sakura/.local/share/kolir/install.sh): Idempotent installer creating symlinks/loaders and checking Arch/AUR packages.
- [dice.zsh-theme](file:///home/sakura/.local/share/kolir/dice.zsh-theme), [zshrc](file:///home/sakura/.local/share/kolir/zshrc): Custom Oh My Zsh theme and shell profile.

## 3. Data Flow
```
Wallpaper Event (SUPER+CTRL+T / SUPER+CTRL+ALT+T)  -->  scripts/set_wallpaper.sh (awww img)
Theme Switch (Bar ThemeToggle.qml)                 -->  scripts/toggle-theme.sh (~/.cache/current_theme)
                                                                 │
                                                                 ▼
                                                  scripts/generate_colors.sh
                                                    reads awww cache & theme
                                                    executes: matugen image
                                                                 │
                    ┌────────────────────────────┬───────────────┴───────────────┬───────────────────────────┐
                    ▼                            ▼                               ▼                           ▼
        ~/.config/foot/colors.ini    ~/.cache/terminal-sequences    ~/.config/hypr/colors.lua   ~/.config/quickshell/colors.json
        (foot-colors.ini)            (terminal-sequences)           (hyprland-colors.lua)       (quickshell-colors.json)
                    │                            │                               │                           │
         Read on foot startup       tee /dev/pts/* (live foot)      hyprctl reload               Watched by Colors.qml FileView
                                                                    (dofile in hyprland.lua)     (reactive QML property updates)
```
- **Wallpaper Trigger**: Hyprland binds execute `config/hypr/scripts/select_wallpaper.sh` or `random-wallpaper.sh`, which set the image via `awww img` and invoke `generate_colors.sh`.
- **Theme Trigger**: `ThemeToggle.qml` calls `toggle-theme.sh`, which flips `~/.cache/current_theme` (`light`/`dark`), updates GTK/KDE system themes, and invokes `generate_colors.sh`.
- **Palette Generation**: `generate_colors.sh` queries current image from `~/.cache/awww/0.12.1/DP-1` and runs `matugen image <path> --source-color-index 0 -m <theme> --contrast <contrast>`.
- **Consumer Updates**:
  - **Quickshell**: `config/quickshell/theme/Colors.qml` uses `FileView` watching `~/.config/quickshell/colors.json`. `onLoaded` parses JSON and updates camelCase properties dynamically without restarting Quickshell.
  - **Foot**: Matugen broadcasts escape sequences into open pseudo-terminals via `tee /dev/pts/[0-9]* < ~/.cache/terminal-sequences`, updating live windows immediately; new instances read `~/.config/foot/colors.ini`.
  - **Hyprland**: Matugen post-hook executes `hyprctl reload`. `config/hypr/hyprland.lua` imports `~/.config/hypr/colors.lua` via `dofile()`.

## 4. Conventions
- **Shared Components**: Reusable UI primitives live in `config/quickshell/bar/components/` (`Pill.qml`, `Island.qml`, `Surface.qml`, `IconButton.qml`, `AppIcon.qml`, `PixelBox.qml`) and `config/quickshell/Button.qml`.
- **Singletons**: Global services and style registries live in `config/quickshell/theme/` and are registered in `qmldir`. Import `../theme` or `../../theme` to access `Colors`, `Dimensions`, `Typography`, `Icons`, `AudioService`, or `BrightnessService`.
- **Styling**: Always use `Colors.<role>` (Material Design 3 tokens) with `Colors.withAlpha(color, opacity)` or `Colors.stateLayer(color, opacity)`. Dimension tokens belong in `Dimensions.*`, fonts and weights in `Typography.*`, and icon ligatures in `Icons.*`. Never hardcode colors.
- **IPC Handlers**: Modules expose actions via `IpcHandler { target: "<name>" }` (e.g. `launcher`, `brightness`, `volume`, `settings`, `nowPlaying`, `recording`, `recordingSetup`). Trigger them via `qs -p <config_dir> ipc call <target> <method> [args]`.
- **Adding a Module/Widget**:
  1. For top-bar widgets, add `<Widget>.qml` in `config/quickshell/bar/components/` and instantiate it inside `config/quickshell/bar/Bar.qml`.
  2. For standalone overlay panels or windows, place them in their own directory under `config/quickshell/<name>/` and instantiate them inside `ShellRoot` in `config/quickshell/shell.qml`.
  3. Assign a `WlrLayershell.namespace` and configure corresponding layer rules in `config/hypr/hyprland.lua` if blur or anim rules are required.

## 5. How to Verify Changes
- **Quickshell**:
  - Restart shell: `killall quickshell; quickshell -p ~/.local/share/kolir/config/quickshell &` (or `qs -p ~/.local/share/kolir/config/quickshell`).
  - Check logs / stdout: Run `quickshell -p ~/.local/share/kolir/config/quickshell` in a terminal foreground to inspect `console.log()` outputs and QML binding errors.
  - Test IPC controls: `qs -p ~/.local/share/kolir/config/quickshell ipc call <target> <method>` (e.g. `qs -p ~/.local/share/kolir/config/quickshell ipc call launcher toggle`).
- **Hyprland**:
  - Reload compositor: `hyprctl reload`.
  - Read logs: `cat "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"`.

## 6. Do Not Edit (Generated Files & Real Sources)
- `~/.config/hypr/colors.lua`: Generated by Matugen. Source template: [config/matugen/templates/hyprland-colors.lua](file:///home/sakura/.local/share/kolir/config/matugen/templates/hyprland-colors.lua).
- `~/.config/foot/colors.ini`: Generated by Matugen. Source template: [config/matugen/templates/foot-colors.ini](file:///home/sakura/.local/share/kolir/config/matugen/templates/foot-colors.ini).
- `~/.config/quickshell/colors.json`: Generated by Matugen. Source template: `~/.config/matugen/templates/quickshell-colors.json`. (Repo `config/quickshell/colors.json` is a bundled fallback).
- `~/.cache/terminal-sequences`: Generated by Matugen. Source template: [config/matugen/templates/terminal-sequences](file:///home/sakura/.local/share/kolir/config/matugen/templates/terminal-sequences).
- `~/.cache/current_theme`: State file managed by [config/hypr/scripts/toggle-theme.sh](file:///home/sakura/.local/share/kolir/config/hypr/scripts/toggle-theme.sh).
- `$XDG_RUNTIME_DIR/kolir/*`: Ephemeral recorder state files (`recording.json`, `record.pid`, etc.) written by `screen-record.sh`.
- `~/.config/hypr/hyprland.lua`: Installed as a loader stub delegating to this repository. Machine-specific overrides belong in `~/.config/hypr/user.lua` (see [config/hypr/user.lua.example](file:///home/sakura/.local/share/kolir/config/hypr/user.lua.example)).
- `~/.config/foot/foot.ini`: Installed as a loader including the repo config and generated colors.

## 7. Environment Notes
- **OS & Window Manager**: Arch Linux, Wayland, Hyprland 0.57.2.
- **Quickshell**: Version 0.3.2. Relies on `Quickshell.Io` (`Process`, `FileView`, `SplitParser`, `StdioCollector`, `IpcHandler`), `Quickshell.Wayland` (`WlrLayershell`), and `Quickshell.Services` (`Notifications`, `Mpris`).
- **Known Quirks & Pitfalls**:
  - **Hardcoded paths in Launcher**: `config/quickshell/launcher/Launcher.qml` contains hardcoded paths referencing `/home/sakura/.local/share/kolir/config/quickshell/launcher/cliphist-*.py`.
  - **Hardcoded monitor & cache version**: `config/hypr/scripts/generate_colors.sh` hardcodes monitor `DP-1` and awww version `0.12.1` in `~/.cache/awww/0.12.1/DP-1`. Changing monitor port or upgrading awww breaks wallpaper path discovery.
  - **Template divergence**: The active `~/.config/matugen/config.toml` and `~/.config/matugen/templates/` contain templates (e.g. `quickshell-colors.json`, `gtk3`, `gtk4`, `zen-colors`, `obsidian`) not currently tracked in the repo's `config/matugen/`.
  - **Lua Configuration**: Hyprland configuration uses the modern Lua API (`hl.config`, `hl.bind`, `hl.window_rule`, `hl.layer_rule`), not traditional `hyprland.conf` directives.
  - **Hybrid Brightness**: `brightness.sh` adjusts internal display via `brightnessctl` and external display via Quickshell IPC calling `BrightnessService.qml` (which throttles `ddcutil setvcp 10`).

## 8. Open Questions
- Should `~/.config/matugen/templates/quickshell-colors.json` and the updated `config.toml` entries be committed to the repository's `config/matugen/` to make color generation fully reproducible on fresh checkouts?
