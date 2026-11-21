# AGENTS.md — Desktop Environment Reference

## 1. Overview
`kolir` is an Arch Linux desktop configuration for a Wayland session built on Hyprland (configured with Lua) and a custom Quickshell (QML) shell. The shell is Material Design 3–inspired: the bar is a full-screen top-layer surface that paints the bar strip and hosts an embedded settings popout, while a separate bottom-layer frame surface fills the window gaps and frames the desktop below windows. The shell also owns a separate sound popup. Matugen extracts a neutral Material 3 palette from the current wallpaper and reactively updates Hyprland, Foot, Neovim, and (when configured) Quickshell colors. Machine-specific Hyprland settings live in `~/.config/hypr/user.lua`; the installer deploys thin loaders and symlinks from this repository.

## 2. Directory Map
- [config/hypr/hyprland.lua](file:///home/sakura/.local/share/kolir/config/hypr/hyprland.lua): Shared Hyprland config using the Lua API (`hl.config`, `hl.bind`, `hl.window_rule`, `hl.layer_rule`, `hl.animation`). Loads generated `~/.config/hypr/colors.lua` when present, defines keybinds (screenshots, wallpapers, recording, media/brightness keys), and loads `~/.config/hypr/user.lua` last.
- [config/hypr/user.lua.example](file:///home/sakura/.local/share/kolir/config/hypr/user.lua.example): Template for the untracked machine-specific file (`monitors`, autostart, cursor/env, personal binds, overrides).
- [config/hypr/hyprsunset.conf](file:///home/sakura/.local/share/kolir/config/hypr/hyprsunset.conf): Valid hyprlang config for the blue-light filter. Runtime control and the automatic schedule are owned by Quickshell (`HyprsunsetService`), so native `profile { ... }` blocks should stay commented out.
- [config/hypr/scripts/](file:///home/sakura/.local/share/kolir/config/hypr/scripts): Helper scripts:
  - `set-wallpaper.sh`: applies an image with `awww img -t random --transition-fps 180`.
  - `select-wallpaper.sh` / `random-wallpaper.sh`: pick a wallpaper with Zenity or `find`+`shuf`, then call `set-wallpaper.sh` and `generate_colors.sh`.
  - `generate_colors.sh`: reads the awww cache and theme state, then runs Matugen with the neutral scheme.
  - `toggle-theme.sh`: flips `~/.cache/current_theme`, updates GTK/KDE theme names, and regenerates colors.
  - `brightness.sh`: adjusts the internal panel with `brightnessctl` and the external monitor through Quickshell IPC.
  - `screen-record.sh`: recording toggle/setup/start with `wf-recorder` (fallback `wl-screenrec`), audio mixing, encoder selection, and state files under `$XDG_RUNTIME_DIR/kolir`.
- [config/quickshell/shell.qml](file:///home/sakura/.local/share/kolir/config/quickshell/shell.qml): Quickshell `ShellRoot`. Instantiates `Frame`, `Bar`, `Launcher`, `Notification`, `VolumeOsd`, `BrightnessOsd`, and `RecordingSetup`; settings is embedded in `Bar`.
- [config/quickshell/bar/](file:///home/sakura/.local/share/kolir/config/quickshell/bar): Top panel and screen frame. [Bar.qml](file:///home/sakura/.local/share/kolir/config/quickshell/bar/Bar.qml) is a full-screen Top-layer `PanelWindow` that paints and accepts input only on the 30px bar strip (the whole surface while settings is open). Layout: settings trigger, active window, now playing, workspaces, clock/keyboard layout, tray, recording indicator, brightness, volume, theme toggle. It also hosts `SettingsMenu` as an overlay so the popout shares the bar surface. [Frame.qml](file:///home/sakura/.local/share/kolir/config/quickshell/bar/Frame.qml) is a full-screen Bottom-layer `PanelWindow` that paints the window gaps and the rounded desktop cut-out below windows; it is click-through and its corners cannot clip window borders.
- [config/quickshell/bar/components/](file:///home/sakura/.local/share/kolir/config/quickshell/bar/components): UI primitives and widgets. Used primitives: `Surface`, `Pill`, `IconButton`, `AppIcon`, `ProgressIndicator`, `VolumeSlider`. Widgets: `ActiveWindow`, `Workspaces`, `NowPlaying` (expandable MPRIS island with transport controls), `Clock`, `KeyboardLayout`, `Tray`, `TrayButton`, `TrayMenu`, `RecordingStatus`, `Brightness`, `Volume`, `ThemeToggle`; `VolumePopup` + `SoundControls` implement the sound popup (output/input volume, device lists, Bluetooth codec chips); `BrightnessPopup` is the right-click night-light menu (filter toggle, temperature presets/slider, fixed times or sunrise/sunset schedule); `SunTimeCard` renders its read-only solar times. `Island.qml` and `PixelBox.qml` are legacy and currently unreferenced.
- [config/quickshell/theme/](file:///home/sakura/.local/share/kolir/config/quickshell/theme): Singletons declared in `qmldir`: `Colors`, `Dimensions`, `Typography`, `Icons`, `AudioService`, `BrightnessService`, `HyprsunsetService`.
- [config/quickshell/launcher/](file:///home/sakura/.local/share/kolir/config/quickshell/launcher): App launcher with scored search, math evaluation, and clipboard mode (`;` prefix) backed by `cliphist-*.py` helpers and `cliphist`/`wl-clipboard`.
- [config/quickshell/settings/](file:///home/sakura/.local/share/kolir/config/quickshell/settings): Embedded settings popout ([SettingsMenu.qml](file:///home/sakura/.local/share/kolir/config/quickshell/settings/SettingsMenu.qml)) with a main page and Bluetooth/Internet pages, plus the controlled `Toggle` switch. Sound settings are no longer a page here; they live in the bar volume popup.
- [config/quickshell/notification/](file:///home/sakura/.local/share/kolir/config/quickshell/notification): Wayland notification daemon and overlay cards (`Notification.qml`).
- [config/quickshell/osd/](file:///home/sakura/.local/share/kolir/config/quickshell/osd): Bottom-center volume and brightness OSDs with wavy Material 3 progress indicators.
- [config/quickshell/rec/](file:///home/sakura/.local/share/kolir/config/quickshell/rec): One-shot recording setup panel (`RecordingSetup.qml`); passes choices to `screen-record.sh --start`.
- [config/quickshell/corners/](file:///home/sakura/.local/share/kolir/config/quickshell/corners): Legacy `Corner.qml` rounding mask. It is not instantiated; the bottom-layer frame (`bar/Frame.qml`) now handles the desktop corners.
- [config/matugen/config.toml](file:///home/sakura/.local/share/kolir/config/matugen/config.toml): Matugen outputs for Foot, live terminal sequences, Neovim, and Hyprland. The active local config also contains additional templates not tracked here.
- [config/matugen/templates/](file:///home/sakura/.local/share/kolir/config/matugen/templates): Tracked templates: `foot-colors.ini`, `terminal-sequences`, `nvim-colors.lua`, `hyprland-colors.lua`.
- [config/foot/](file:///home/sakura/.local/share/kolir/config/foot): Foot base config (`foot.ini`) and a bundled fallback `colors.ini`.
- [config/mpv/mpv.conf](file:///home/sakura/.local/share/kolir/config/mpv/mpv.conf): MPV configuration.
- [install.sh](file:///home/sakura/.local/share/kolir/install.sh): Idempotent installer. Supports curl/bootstrap mode, checks/installs Arch and AUR packages, installs Oh My Zsh/plugins/theme, and deploys the Hyprland/Foot loaders plus Matugen, MPV, and zsh symlinks. Quickshell is run directly from the repo (`qs -p <repo>/config/quickshell`).
- [dice.zsh-theme](file:///home/sakura/.local/share/kolir/dice.zsh-theme), [zshrc](file:///home/sakura/.local/share/kolir/zshrc): Oh My Zsh theme and shell profile.
- [config/quickshell/Button.qml](file:///home/sakura/.local/share/kolir/config/quickshell/Button.qml): Legacy standalone button; currently unreferenced.

## 3. Data Flow
```
Wallpaper (SUPER+CTRL+T select / SUPER+CTRL+ALT+T random)
        └─> select-wallpaper.sh / random-wallpaper.sh
              └─> set-wallpaper.sh (awww img)
                    └─> generate_colors.sh
Theme toggle (Bar ThemeToggle.qml)
        └─> toggle-theme.sh (~/.cache/current_theme, GTK/KDE theme)
              └─> generate_colors.sh
generate_colors.sh
  reads ~/.cache/awww/0.12.1/DP-1 and ~/.cache/current_theme
  runs: matugen image <path> --source-color-index 0 -m <theme> -t scheme-neutral
        ├─> ~/.config/foot/colors.ini
        ├─> ~/.cache/terminal-sequences  ──> tee /dev/pts/* (live Foot)
        ├─> ~/.local/share/nvim/matugen-colors.lua
        ├─> ~/.config/hypr/colors.lua    ──> hyprctl reload
        └─> ~/.config/quickshell/colors.json (only if the active Matugen config defines it)
```
- **Wallpaper Trigger**: The Hyprland binds run `config/hypr/scripts/select-wallpaper.sh` or `random-wallpaper.sh`. Both call `set-wallpaper.sh` (`awww img`) and then `generate_colors.sh`.
- **Theme Trigger**: `ThemeToggle.qml` watches `~/.cache/current_theme` and calls `toggle-theme.sh`. The script flips `light`/`dark`, updates GNOME/GTK and KDE theme settings, writes the state file, and calls `generate_colors.sh`.
- **Palette Generation**: `generate_colors.sh` is zsh-based and currently hardcodes the awww cache path (`~/.cache/awww/0.12.1/DP-1`) and monitor (`DP-1`). It runs Matugen with `--source-color-index 0` and `-t scheme-neutral` (the contrast branch is commented out).
- **Consumer Updates**:
  - **Quickshell**: `config/quickshell/theme/Colors.qml` watches `~/.config/quickshell/colors.json` with `FileView`, parses it in `onLoaded`, and maps snake_case keys to camelCase QML properties without restarting the shell.
  - **Foot**: Matugen writes `~/.cache/terminal-sequences`; its `post_hook` tees ANSI color sequences into open pseudo-terminals. New Foot instances read `~/.config/foot/colors.ini`.
  - **Neovim**: Matugen writes `~/.local/share/nvim/matugen-colors.lua` from the tracked `nvim-colors.lua` template.
  - **Hyprland**: The Matugen `post_hook` runs `hyprctl reload`; `hyprland.lua` loads `~/.config/hypr/colors.lua` with `dofile()` when it exists.
  - **GTK/KDE**: `toggle-theme.sh` changes GTK color-scheme/theme and KDE `ColorScheme`; these are not Matugen template outputs in the tracked config.

## 4. Conventions
- **Shared Components**: Reusable UI primitives live in `config/quickshell/bar/components/` (`Surface.qml`, `Pill.qml`, `IconButton.qml`, `AppIcon.qml`, `ProgressIndicator.qml`, `VolumeSlider.qml`). Prefer these over duplicating surface styling.
- **Singletons**: Global services and style registries live in `config/quickshell/theme/` and are registered in `qmldir`. Import `../theme` or `../../theme` to access `Colors`, `Dimensions`, `Typography`, `Icons`, `AudioService`, `BrightnessService`, or `HyprsunsetService`.
- **Styling**: Use `Colors.<role>` (Material Design 3 tokens) with `Colors.withAlpha(color, opacity)` or `Colors.stateLayer(color, opacity)`. Dimensions belong in `Dimensions.*` (including `Dimensions.progress.*` for progress indicators), fonts/weights in `Typography.*`, and icon ligatures in `Icons.*`. Never hardcode colors.
- **Frame Geometry**: `Frame.qml` assumes `Dimensions.frame.thickness` equals Hyprland's `general.gaps_out` (currently `4`), and `Dimensions.frame.radius` equals `decoration.rounding + border_size` (`28 + 2 = 30`). The frame path starts at `Dimensions.bar.height` because `Bar.qml` paints the 30px bar strip above it. Keep these in sync when changing gaps, rounding, or border size.
- **IPC Handlers**: Modules expose actions via `IpcHandler { target: "<name>" }`. Current targets: `launcher`, `brightness`, `volume`, `settings`, `nowPlaying`, `recording`, `recordingSetup`, `hyprsunset`, `nightLight`. Trigger them with `qs -p <config_dir> ipc call <target> <method> [args]`.
- **Layer Namespaces**: `frame`, `bar`, `launcher`, `notifications`, `volume-osd`, `brightness-osd`, and `recording-setup`. `hyprland.lua` currently adds blur rules for `bar`, `launcher`, and `recording-setup`; `frame` is a Bottom-layer decorative surface and needs no blur rule.
- **Bar vs. Panels**:
  1. For a top-bar widget, add `<Widget>.qml` under `config/quickshell/bar/components/` and instantiate it in `Bar.qml`.
  2. For a standalone overlay, add a component under its own `config/quickshell/<name>/` directory and instantiate it in `ShellRoot` (`shell.qml`); give it a `WlrLayershell.namespace` and add layer rules in `hyprland.lua` when blur/anim is needed.
  3. Settings belongs inside `SettingsMenu.qml` because the popout is drawn in the bar surface: add a `MainPage.entries` item, a page component, and a height in `heightForPage()`. The bar expands its input mask and enables `WlrKeyboardFocus.OnDemand` while settings is open.
  4. Focus-grabbing popups (for example `VolumePopup`) use `PopupWindow` + `HyprlandFocusGrab` rather than a layer-shell window.
  5. The decorative screen frame belongs in `bar/Frame.qml` on `WlrLayer.Bottom` with an empty `mask`; keep it below windows and click-through. Do not move it into the top-layer `Bar` surface, or the window border is clipped at the rounded cut-out.

## 5. How to Verify Changes
- **Quickshell**:
  - Restart shell: `killall quickshell; quickshell -p ~/.local/share/kolir/config/quickshell &` (or `qs -p ~/.local/share/kolir/config/quickshell`).
  - Check logs: run `quickshell -p ~/.local/share/kolir/config/quickshell` in a terminal foreground to inspect `console.log()` output and QML binding errors.
  - Test IPC:
    - `qs -p ~/.local/share/kolir/config/quickshell ipc call launcher toggle`
    - `qs -p ~/.local/share/kolir/config/quickshell ipc call settings toggle`
    - `qs -p ~/.local/share/kolir/config/quickshell ipc call volume toggle`
    - `qs -p ~/.local/share/kolir/config/quickshell ipc call nowPlaying playPause`
    - `qs -p ~/.local/share/kolir/config/quickshell ipc call recordingSetup open`
- **Hyprland**:
  - Reload compositor: `hyprctl reload`.
  - Inspect layer namespaces: `hyprctl layers` (`frame` should be on the Bottom level, `bar` on Top).
  - Read logs: `cat "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"`.
- **Installer**: run `./install.sh`; it prints the full package/config plan and asks for confirmation before changing anything.

## 6. Do Not Edit (Generated Files & Real Sources)
- `~/.config/hypr/colors.lua`: Generated by Matugen. Source template: [config/matugen/templates/hyprland-colors.lua](file:///home/sakura/.local/share/kolir/config/matugen/templates/hyprland-colors.lua).
- `~/.config/foot/colors.ini`: Generated by Matugen. Source template: [config/matugen/templates/foot-colors.ini](file:///home/sakura/.local/share/kolir/config/matugen/templates/foot-colors.ini). The repo copy is a bundled fallback.
- `~/.cache/terminal-sequences`: Generated by Matugen. Source template: [config/matugen/templates/terminal-sequences](file:///home/sakura/.local/share/kolir/config/matugen/templates/terminal-sequences).
- `~/.local/share/nvim/matugen-colors.lua`: Generated by Matugen. Source template: [config/matugen/templates/nvim-colors.lua](file:///home/sakura/.local/share/kolir/config/matugen/templates/nvim-colors.lua).
- `~/.config/quickshell/colors.json`: Generated by Matugen only when the active local `~/.config/matugen/config.toml` defines the `quickshell` template. The repo `config/quickshell/colors.json` is a bundled snapshot, not the file `Colors.qml` watches; the tracked Matugen config does not currently generate it.
- `~/.cache/current_theme`: State file managed by [config/hypr/scripts/toggle-theme.sh](file:///home/sakura/.local/share/kolir/config/hypr/scripts/toggle-theme.sh).
- `~/.cache/quickshell/hyprsunset.json`: Night-light state, schedule mode/times and cached solar location (`enabled`, `temperature`, `auto`, `mode`, `on`, `off`, `latitude`, `longitude`, `city`, `country`, `locationUpdated`) written by `HyprsunsetService.qml`; edit through the bar menu, not by hand.
- `$XDG_RUNTIME_DIR/kolir/*`: Ephemeral recorder state (`recording.json`, `record.pid`, `record.file`, `record.started`, `record.lock`, `recorder.log`, etc.) written by `screen-record.sh` and watched by `RecordingStatus.qml`.
- `~/.config/hypr/hyprland.lua`: Installed as a loader stub delegating to this repository. Machine-specific overrides belong in `~/.config/hypr/user.lua`.
- `~/.config/foot/foot.ini`: Installed as a loader including the repo `foot.ini` and the generated `~/.config/foot/colors.ini`.
- `~/.config/matugen/config.toml` and `~/.config/matugen/templates/`: Installed as symlinks to this repository by `install.sh`. Edit the repo sources, not the local links.
- `~/.config/hypr/scripts`, `~/.config/hypr/hyprsunset.conf`, `~/.config/mpv/mpv.conf`, and `~/.zshrc`: Installed as symlinks to this repository.

## 7. Environment Notes
- **OS & Window Manager**: Arch Linux, Wayland, Hyprland 0.57.2.
- **Quickshell**: Version 0.3.2. Uses `Quickshell.Io` (`Process`, `FileView`, `SplitParser`, `StdioCollector`, `IpcHandler`), `Quickshell.Wayland` (`WlrLayershell`), `Quickshell.Hyprland`, `Quickshell.Services.Notifications`, `Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`, and `Quickshell.Bluetooth`.
- **Runtime Dependencies**: `install.sh` covers the base desktop stack, but the code also expects tools not guaranteed by its package list: `cliphist` (launcher clipboard), `nmcli`/NetworkManager (Internet settings page), BlueZ (Bluetooth settings page and `Quickshell.Bluetooth`), and the `ffmpeg` binary (recording encoder probing). `pactl` comes from `libpulse`, which `pipewire-pulse` pulls in.
- **Known Quirks & Pitfalls**:
  - **Hardcoded paths in Launcher**: `config/quickshell/launcher/Launcher.qml` hardcodes `/home/sakura/.local/share/kolir/config/quickshell/launcher/cliphist-*.py` for its daemons and image preview generation.
  - **Hardcoded monitor & cache version**: `config/hypr/scripts/generate_colors.sh` hardcodes monitor `DP-1` and awww version `0.12.1` in `~/.cache/awww/0.12.1/DP-1`. Changing the monitor port or upgrading awww breaks wallpaper path discovery. The script uses `-t scheme-neutral`; the old contrast logic is commented out.
  - **Matugen template divergence**: The active `~/.config/matugen/config.toml` and templates may contain `quickshell-colors.json`, `gtk3`, `gtk4`, `zen-colors`, and `obsidian` entries that are not tracked in the repo. Because `install.sh` symlinks the repo config/templates, those extra outputs disappear on a fresh deployment unless committed.
  - **Lua Configuration**: Hyprland uses the modern Lua API (`hl.config`, `hl.bind`, `hl.window_rule`, `hl.layer_rule`), not traditional `hyprland.conf` directives.
  - **Hybrid Brightness**: `brightness.sh` adjusts the internal display via `brightnessctl` and the external display via Quickshell IPC calling `BrightnessService.qml`, which throttles `ddcutil setvcp 10`.
  - **Hyprsunset Authority**: `HyprsunsetService` queries `hyprctl hyprsunset identity get/temperature` and reconciles the live CTM every 30 seconds. Direct CLI changes are reverted to the bar state. The automatic schedule lives in Quickshell; native `hyprsunset.conf` profiles must stay disabled to avoid two planners.
  - **Sun Schedule Location**: The sunrise/sunset mode computes NOAA solar times from coordinates detected through `https://ipwho.is/` (`curl`, max 8 s) and cached in the state file for seven days. The refresh button in the popup forces a new lookup; without a cached location the service falls back to the saved manual filter state and disables the schedule toggle.
  - **Bar Frame Coupling**: The bar is a full-screen Top-layer surface whose input mask covers only the 30px bar strip (the whole surface while settings is open). The decorative frame is a separate full-screen Bottom-layer surface (`bar/Frame.qml`) with an empty input region; windows are composited above it, so their borders are never clipped by the rounded cut-out. `Dimensions.frame.thickness` must match Hyprland `gaps_out`, `Dimensions.frame.radius` must match `decoration.rounding + border_size`, and the frame path starts at `Dimensions.bar.height` because `Bar.qml` paints the strip above it. The settings popout lives in the bar surface and switches it to a full-screen modal mask while open.
  - **Volume Popup Focus**: `VolumePopup.qml` is a `PopupWindow` anchored to the volume pill and uses `HyprlandFocusGrab` to close on outside clicks; it is not a layer-shell namespace.
  - **MPRIS Workaround**: `NowPlaying.qml` sends raw `busctl` Play/Pause calls because some players (Firefox/Zen) report stale `PlaybackStatus`, which breaks Quickshell's `togglePlaying()`.
  - **Suspect Hyprland Rule**: In `hyprland.lua`, the Zen browser opacity/blur block is written as `hl.window_rule = { ... }` (an assignment) rather than `hl.window_rule({ ... })`. Treat that rule as ineffective until corrected.
  - **Legacy QML**: `config/quickshell/corners/Corner.qml`, `bar/components/Island.qml`, `bar/components/PixelBox.qml`, and `config/quickshell/Button.qml` are currently unreferenced. The bottom-layer frame replaced the old corner mask.

## 8. Open Questions
- Should `~/.config/matugen/templates/quickshell-colors.json` and the extra Matugen entries (GTK3/GTK4, Zen, Obsidian) be committed to `config/matugen/` so color generation is reproducible on a fresh checkout?
- Should the unreferenced `Corner.qml`, `Island.qml`, `PixelBox.qml`, and `Button.qml` be deleted, or are they intentionally kept for future use?
