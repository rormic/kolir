# AGENTS.md — Desktop Environment Reference

## 1. Overview
`kolir` is an Arch Linux desktop configuration for a Wayland session built on Hyprland (configured with Lua) and a custom Quickshell (QML) shell. The shell is Material Design 3–inspired: the bar is a full-screen top-layer surface that paints the bar strip and hosts an embedded settings popout, while a separate bottom-layer frame surface fills the window gaps and frames the desktop below windows. The shell also owns a separate sound popup. Matugen extracts a neutral Material 3 palette from the current wallpaper and reactively updates Hyprland, Foot, Neovim, and (when configured) Quickshell colors. Machine-specific Hyprland settings live in `~/.config/hypr/user.lua`; the installer deploys thin loaders and symlinks from this repository.

## 2. Directory Map
- [config/hypr/hyprland.lua](file:///home/sakura/.local/share/kolir/config/hypr/hyprland.lua): Shared Hyprland config using the Lua API (`hl.config`, `hl.bind`, `hl.window_rule`, `hl.layer_rule`, `hl.animation`). Loads generated `~/.config/hypr/colors.lua` when present, defines keybinds (screenshots, wallpapers, recording, media/brightness keys), and loads `~/.config/hypr/user.lua` last.
- [config/hypr/user.lua.example](file:///home/sakura/.local/share/kolir/config/hypr/user.lua.example): Template for the untracked machine-specific file (`monitors`, autostart, cursor/env, personal binds, overrides).
- [config/hypr/hyprsunset.conf](file:///home/sakura/.local/share/kolir/config/hypr/hyprsunset.conf): Valid hyprlang config for the blue-light filter. Runtime control and the automatic schedule are owned by Quickshell (`HyprsunsetService`), so native `profile { ... }` blocks should stay commented out.
- [config/hypr/scripts/](file:///home/sakura/.local/share/kolir/config/hypr/scripts): Helper scripts, all `kebab-case`:
  - `set-wallpaper.sh`: applies an image with `awww img -t random --transition-fps 180`.
  - `select-wallpaper.sh` / `random-wallpaper.sh`: pick a wallpaper with Zenity or `find`+`shuf`, then call `set-wallpaper.sh` and `generate-colors.sh`.
  - `generate-colors.sh`: reads the awww cache and theme state, then runs Matugen with the neutral scheme.
  - `toggle-theme.sh`: flips `~/.cache/current_theme`, updates GTK/KDE theme names, and regenerates colors.
  - `brightness.sh`: adjusts the internal panel with `brightnessctl` and the external monitor through Quickshell IPC.
  - `screen-record.sh`: recording toggle/setup/start with `wf-recorder` (fallback `wl-screenrec`), audio mixing, encoder selection, and state files under `$XDG_RUNTIME_DIR/kolir`. It sources `screen-record/audio.sh`, `screen-record/encoders.sh`, and `screen-record/monitors.sh` through `SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)`.
- [config/quickshell/shell.qml](file:///home/sakura/.local/share/kolir/config/quickshell/shell.qml): Quickshell `ShellRoot`. Instantiates `Frame`, `Bar`, `Launcher`, `Notification`, `VolumeOsd`, `BrightnessOsd`, and `RecordingSetup`; settings is embedded in `Bar`.
- [config/quickshell/bar/](file:///home/sakura/.local/share/kolir/config/quickshell/bar): Top panel and screen frame. [Bar.qml](file:///home/sakura/.local/share/kolir/config/quickshell/bar/Bar.qml) is a full-screen Top-layer `PanelWindow` that paints and accepts input only on the 30px bar strip (the whole surface while settings is open). Layout: settings trigger, active window, now playing, workspaces, clock/keyboard layout, tray, recording indicator, brightness, volume, theme toggle. It also hosts `SettingsMenu` as an overlay so the popout shares the bar surface. [Frame.qml](file:///home/sakura/.local/share/kolir/config/quickshell/bar/Frame.qml) is a full-screen Bottom-layer `PanelWindow` that paints the window gaps and the rounded desktop cut-out below windows; it is click-through and its corners cannot clip window borders.
- [config/quickshell/bar/components/](file:///home/sakura/.local/share/kolir/config/quickshell/bar/components): UI primitives and widgets. Primitives: `Surface`, `Pill`, `IconButton`, `AppIcon`, `ProgressIndicator`, `VolumeSlider`. Widgets: `ActiveWindow`, `Workspaces`, `NowPlaying` (expandable MPRIS island), `Clock`, `KeyboardLayout`, `Tray`, `TrayButton`, `TrayMenu`, `TrayMenuPane`, `RecordingStatus`, `Brightness`, `Volume`, `ThemeToggle`, `Toggle`. `VolumePopup` + `SoundControls` implement the sound popup; `BrightnessPopup` is the right-click night-light menu; `SunTimeCard` renders read-only solar times. Subdirectories: `media/` (`MarqueeText`, `MprisController`), `sound/` (`AudioDeviceCard`, `AudioDeviceList`, `CodecChip`), `nightLight/` (`TemperatureCard`, `ScheduleCard`, `TimeField`).
- [config/quickshell/components/](file:///home/sakura/.local/share/kolir/config/quickshell/components): Cross-feature controls. Currently `AnchoredPopup.qml` (focus-grabbing anchored popup mechanics).
- [config/quickshell/theme/](file:///home/sakura/.local/share/kolir/config/quickshell/theme): Visual-only singletons declared in `qmldir`: `Colors`, `Dimensions`, `Typography`, `Icons`, `Motion`. No services or path contracts here.
- [config/quickshell/services/](file:///home/sakura/.local/share/kolir/config/quickshell/services): Runtime singletons and path contracts declared in `qmldir`: `AudioService`, `BrightnessService`, `HyprsunsetService`, `ShellPaths`.
- [config/quickshell/settings/](file:///home/sakura/.local/share/kolir/config/quickshell/settings): Embedded settings popout (`SettingsMenu.qml`) with `MainPage`, Bluetooth and Internet pages, `SettingsPageHeader`, and the shared `PasswordField`. `internet/` contains `NetworkController`, `EthernetCard`, `WifiConnectionForm`, `WifiNetworkRow`; `bluetooth/` contains `BluetoothDeviceRow`. Sound settings are not a page here; they live in the bar volume popup.
- [config/quickshell/launcher/](file:///home/sakura/.local/share/kolir/config/quickshell/launcher): App launcher with scored search, math evaluation, and clipboard mode (`;` prefix). `ClipboardController.qml` lives in a root `Scope` and owns the `cliphist-watch.sh` clipboard watchers and clipboard model; `SearchLogic.js` holds pure search/calculator functions; `LauncherResultRow.qml` renders rows.
- [config/quickshell/notification/](file:///home/sakura/.local/share/kolir/config/quickshell/notification): Wayland notification daemon (`Notification.qml`) and overlay cards (`NotificationCard.qml`).
- [config/quickshell/osd/](file:///home/sakura/.local/share/kolir/config/quickshell/osd): Shared `OsdPanel` plus the bottom-center `VolumeOsd` and `BrightnessOsd` with wavy Material 3 progress indicators.
- [config/quickshell/recording/](file:///home/sakura/.local/share/kolir/config/quickshell/recording): One-shot recording setup panel (`RecordingSetup.qml`) with `RecordingOptions.qml` and `OptionRow.qml`; passes choices to `screen-record.sh --start`.
- [config/quickshell/scripts/](file:///home/sakura/.local/share/kolir/config/quickshell/scripts): Helpers bundled with the shell: `favicon.py`, `cliphist-store.py`, `cliphist-previews.py`, the `cliphist-watch.sh` singleton wrapper around `wl-paste --watch`, and the `pactl-subscribe.sh` singleton wrapper around `pactl subscribe`. QML reaches them through `ShellPaths`.
- [config/matugen/config.toml](file:///home/sakura/.local/share/kolir/config/matugen/config.toml): Matugen outputs for Foot, live terminal sequences, Neovim, and Hyprland. The active local config also contains additional templates not tracked here.
- [config/matugen/templates/](file:///home/sakura/.local/share/kolir/config/matugen/templates): Tracked templates: `foot-colors.ini`, `terminal-sequences`, `nvim-colors.lua`, `hyprland-colors.lua`.
- [config/foot/](file:///home/sakura/.local/share/kolir/config/foot): Foot base config (`foot.ini`) and a bundled fallback `colors.ini`.
- [config/mpv/mpv.conf](file:///home/sakura/.local/share/kolir/config/mpv/mpv.conf): MPV configuration.
- [install.sh](file:///home/sakura/.local/share/kolir/install.sh): Idempotent installer. Supports curl/bootstrap mode, checks/installs Arch and AUR packages, installs Oh My Zsh/plugins/theme, and deploys the Hyprland/Foot loaders plus Matugen, MPV, and zsh symlinks. Quickshell is run directly from the repo (`qs -p <repo>/config/quickshell`).
- [dice.zsh-theme](file:///home/sakura/.local/share/kolir/dice.zsh-theme), [zshrc](file:///home/sakura/.local/share/kolir/zshrc): Oh My Zsh theme and shell profile.

## 3. Data Flow
```
Wallpaper (SUPER+CTRL+T select / SUPER+CTRL+ALT+T random)
        └─> select-wallpaper.sh / random-wallpaper.sh
              └─> set-wallpaper.sh (awww img)
                    └─> generate-colors.sh
Theme toggle (Bar ThemeToggle.qml)
        └─> toggle-theme.sh (~/.cache/current_theme, GTK/KDE theme)
              └─> generate-colors.sh
generate-colors.sh
  reads ~/.cache/awww/0.12.1/DP-1 and ~/.cache/current_theme
  runs: matugen image <path> --source-color-index 0 -m <theme> -t scheme-neutral
        ├─> ~/.config/foot/colors.ini
        ├─> ~/.cache/terminal-sequences  ──> tee /dev/pts/* (live Foot)
        ├─> ~/.local/share/nvim/matugen-colors.lua
        ├─> ~/.config/hypr/colors.lua    ──> hyprctl reload
        └─> ~/.config/quickshell/colors.json (only if the active Matugen config defines it)
```
- **Wallpaper Trigger**: The Hyprland binds run `config/hypr/scripts/select-wallpaper.sh` or `random-wallpaper.sh`. Both call `set-wallpaper.sh` (`awww img`) and then `generate-colors.sh`.
- **Theme Trigger**: `ThemeToggle.qml` watches `~/.cache/current_theme` and calls `toggle-theme.sh`. The script flips `light`/`dark`, updates GNOME/GTK and KDE theme settings, writes the state file, and calls `generate-colors.sh`.
- **Palette Generation**: `generate-colors.sh` is zsh-based and currently hardcodes the awww cache path (`~/.cache/awww/0.12.1/DP-1`) and monitor (`DP-1`). It runs Matugen with `--source-color-index 0` and `-t scheme-neutral`.
- **Consumer Updates**:
  - **Quickshell**: `config/quickshell/theme/Colors.qml` watches `ShellPaths.colorsJson` with `FileView`, parses it in `onLoaded`, and maps snake_case keys to camelCase QML properties without restarting the shell.
  - **Foot**: Matugen writes `~/.cache/terminal-sequences`; its `post_hook` tees ANSI color sequences into open pseudo-terminals. New Foot instances read `~/.config/foot/colors.ini`.
  - **Neovim**: Matugen writes `~/.local/share/nvim/matugen-colors.lua` from the tracked `nvim-colors.lua` template.
  - **Hyprland**: The Matugen `post_hook` runs `hyprctl reload`; `hyprland.lua` loads `~/.config/hypr/colors.lua` with `dofile()` when it exists.
  - **GTK/KDE**: `toggle-theme.sh` changes GTK color-scheme/theme and KDE `ColorScheme`; these are not Matugen template outputs in the tracked config.

## 4. Conventions
- **Naming**: QML files and types are `PascalCase`; JavaScript modules are `camelCase`; directories are lowercase except the existing `nightLight/` feature directory; Hyprland shell scripts and `screen-record/` helper modules are `kebab-case`. Preserve IPC targets, layer namespaces, JSON keys, and CLI arguments exactly.
- **Shared Components**: Reusable UI primitives live in `config/quickshell/bar/components/` (`Surface.qml`, `Pill.qml`, `IconButton.qml`, `AppIcon.qml`, `ProgressIndicator.qml`, `VolumeSlider.qml`). Prefer these over duplicating surface styling.
- **Singletons**: Visual tokens live in `config/quickshell/theme/` (`Colors`, `Dimensions`, `Typography`, `Icons`, `Motion`); runtime services and path contracts live in `config/quickshell/services/` (`AudioService`, `BrightnessService`, `HyprsunsetService`, `ShellPaths`). Both directories have their own `qmldir`; import both (`../theme` + `../services`, or the matching `../../` path) when a file needs them.
- **Constants**: `Dimensions` holds repeated geometry and shared metrics; `Typography` holds fonts and type scale; `Icons` holds Material Symbols names; `Motion` holds repeated UI animation roles (`color`, `hover`, `press`, `scale`, `fade`, `move`, `rotate`, `spin`, `popupEnter`, `popupExit`, `listEnter`, `listExit`, `osd`). Popup-specific sizes, optical offsets, process intervals and thresholds stay as local `readonly` properties. Domain constants (FPS, bitrate, CRF, temperatures, search scores, NOAA coefficients) stay local to their feature. Do not tokenize `0`/`1`, SVG coordinates, mathematical coefficients, accent-dot coordinates, or one-off optical tweaks.
- **Paths**: Every path outside the shell config goes through `ShellPaths` (`hyprScripts`, `currentTheme`, `colorsJson`, `hyprsunsetState`, `runtimeDir`, `recordingState`, `clipboardPreviewDir`, `cliphistStore`, `cliphistWatch`, `cliphistPreviews`, `pactlSubscribe`). Do not build `HOME`-based paths in QML.
- **Styling**: Use `Colors.<role>` (Material Design 3 tokens) with `Colors.withAlpha(color, opacity)` or `Colors.stateLayer(color, opacity)`. Dimensions belong in `Dimensions.*` (including `Dimensions.progress.*` for progress indicators), fonts/weights in `Typography.*`, and icon ligatures in `Icons.*`. Never hardcode colors.
- **Frame Geometry**: `Frame.qml` assumes `Dimensions.frame.thickness` equals Hyprland's `general.gaps_out` (currently `4`), and `Dimensions.frame.radius` equals `decoration.rounding + border_size` (`28 + 2 = 30`). The frame path starts at `Dimensions.bar.height` because `Bar.qml` paints the 30px bar strip above it. Keep these in sync when changing gaps, rounding, or border size.
- **IPC Handlers**: Modules expose actions via `IpcHandler { target: "<name>" }`. Current targets: `launcher`, `brightness`, `volume`, `settings`, `nowPlaying`, `recording`, `recordingSetup`, `hyprsunset`, `nightLight`. Trigger them with `qs -p <config_dir> ipc call <target> <method> [args]`.
- **Layer Namespaces**: `frame`, `bar`, `launcher`, `notifications`, `volume-osd`, `brightness-osd`, and `recording-setup`. `hyprland.lua` currently adds blur rules for `bar`, `launcher`, and `recording-setup`; `frame` is a Bottom-layer decorative surface and needs no blur rule. `OsdPanel` receives its namespace from the wrapper (`volume-osd` / `brightness-osd`).
- **Bar vs. Panels**:
  1. For a top-bar widget, add `<Widget>.qml` under `config/quickshell/bar/components/` and instantiate it in `Bar.qml`.
  2. For a standalone overlay, add a component under its own `config/quickshell/<name>/` directory and instantiate it in `ShellRoot` (`shell.qml`); give it a `WlrLayershell.namespace` and add layer rules in `hyprland.lua` when blur/anim is needed.
  3. Settings belongs inside `SettingsMenu.qml` because the popout is drawn in the bar surface: add a `MainPage.entries` item, a page component, and a height in `heightForPage()`. The bar expands its input mask and enables `WlrKeyboardFocus.OnDemand` while settings is open.
  4. Focus-grabbing popups (for example `VolumePopup`) use `PopupWindow` + `HyprlandFocusGrab` rather than a layer-shell window.
  5. The decorative screen frame belongs in `bar/Frame.qml` on `WlrLayer.Bottom` with an empty `mask`; keep it below windows and click-through. Do not move it into the top-layer `Bar` surface, or the window border is clipped at the rounded cut-out.
- **Recording Helpers**: `screen-record.sh` stays the lifecycle/CLI owner. `screen-record/audio.sh` owns PipeWire/Pulse helpers, `encoders.sh` owns encoder/quality selection, and `monitors.sh` owns Hyprland geometry/FPS helpers. Source them from `SCRIPT_DIR`; do not hardcode repo or home paths.

## 5. How to Verify Changes
- **Quickshell**:
  - Restart shell: `pkill -x quickshell; sleep 2; setsid quickshell -p ~/.local/share/kolir/config/quickshell >/tmp/kolir-run.log 2>&1 </dev/null &`.
  - Check logs: run `quickshell -p ~/.local/share/kolir/config/quickshell` in a terminal foreground, or read `/tmp/kolir-run.log`; compare against `/home/sakura/.cache/kolir/qml-baseline.log`. New `ReferenceError`, `TypeError`, `is not a type`, `binding loop`, or `Unable to assign` is a regression.
  - Lint: `/usr/lib/qt6/bin/qmllint $(find config/quickshell -name '*.qml' | sort)`; compare categories with `/home/sakura/.cache/kolir/qml-lint-baseline.txt`. `missing-property` warnings for `Dimensions`/`Typography`/`Icons` are known linter false positives.
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
- **Shell scripts**: `zsh -n` for wallpaper/theme scripts; `sh -n` for `screen-record.sh`, `screen-record/*.sh`, `config/quickshell/scripts/cliphist-watch.sh`, and `config/quickshell/scripts/pactl-subscribe.sh`. Apply the current wallpaper with `set-wallpaper.sh "$(awww query | sed -n 's/.*image: //p')"` and regenerate colors with `generate-colors.sh`.
- **Recording**: start `screen-record.sh --start --area full --audio system|mic|both|none`, stop with `screen-record.sh`, and check `ffprobe` streams, `$XDG_RUNTIME_DIR/kolir/recording.json`, leftover recorder processes, and `pactl list short modules | grep kolir_rec_mix`.
- **Installer**: run `./install.sh`; it prints the full package/config plan and asks for confirmation before changing anything.

## 6. Do Not Edit (Generated Files & Real Sources)
- `~/.config/hypr/colors.lua`: Generated by Matugen. Source template: [config/matugen/templates/hyprland-colors.lua](file:///home/sakura/.local/share/kolir/config/matugen/templates/hyprland-colors.lua).
- `~/.config/foot/colors.ini`: Generated by Matugen. Source template: [config/matugen/templates/foot-colors.ini](file:///home/sakura/.local/share/kolir/config/matugen/templates/foot-colors.ini). The repo copy is a bundled fallback.
- `~/.cache/terminal-sequences`: Generated by Matugen. Source template: [config/matugen/templates/terminal-sequences](file:///home/sakura/.local/share/kolir/config/matugen/templates/terminal-sequences).
- `~/.local/share/nvim/matugen-colors.lua`: Generated by Matugen. Source template: [config/matugen/templates/nvim-colors.lua](file:///home/sakura/.local/share/kolir/config/matugen/templates/nvim-colors.lua).
- `~/.config/quickshell/colors.json`: Generated by Matugen only when the active local `~/.config/matugen/config.toml` defines the `quickshell` template. The repo `config/quickshell/colors.json` is a bundled snapshot, not the file `Colors.qml` watches; the tracked Matugen config does not currently generate it.
- `~/.cache/current_theme`: State file managed by [config/hypr/scripts/toggle-theme.sh](file:///home/sakura/.local/share/kolir/config/hypr/scripts/toggle-theme.sh).
- `~/.cache/quickshell/hyprsunset.json`: Night-light state, schedule mode/times and cached solar location written by `services/HyprsunsetService.qml`; edit through the bar menu, not by hand.
- `$XDG_RUNTIME_DIR/kolir/*`: Ephemeral recorder state (`recording.json`, `record.pid`, `record.file`, `record.started`, `record.lock`, `record.modules`, `recorder.log`) written by `screen-record.sh` and watched by `RecordingStatus.qml`.
- `~/.config/hypr/hyprland.lua`: Installed as a loader stub delegating to this repository. Machine-specific overrides belong in `~/.config/hypr/user.lua`.
- `~/.config/foot/foot.ini`: Installed as a loader including the repo `foot.ini` and the generated `~/.config/foot/colors.ini`.
- `~/.config/hypr/scripts`, `~/.config/hypr/hyprsunset.conf`, `~/.config/mpv/mpv.conf`, `~/.config/matugen/config.toml`, `~/.config/matugen/templates`, and `~/.zshrc`: intended to be symlinks to this repository, created by `install.sh`.
- On the current machine `~/.config/matugen/config.toml`, `~/.config/matugen/templates`, and `~/.zshrc` are still regular files until `install.sh` is re-run; the repository copies remain the source of truth.

## 7. Environment Notes
- **OS & Window Manager**: Arch Linux, Wayland, Hyprland 0.57.2.
- **Quickshell**: Version 0.3.2. Uses `Quickshell.Io` (`Process`, `FileView`, `SplitParser`, `StdioCollector`, `IpcHandler`), `Quickshell.Wayland` (`WlrLayershell`), `Quickshell.Hyprland`, `Quickshell.Services.Notifications`, `Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`, and `Quickshell.Bluetooth`.
- **Runtime Dependencies**: `install.sh` covers the base desktop stack, but the code also expects tools not guaranteed by its package list: `cliphist` (launcher clipboard), `nmcli`/NetworkManager (Internet settings page), BlueZ (Bluetooth settings page and `Quickshell.Bluetooth`), and the `ffmpeg` binary (recording encoder probing). `pactl` comes from `libpulse`, which `pipewire-pulse` pulls in.
- **Known Quirks & Pitfalls**:
  - **Hardcoded monitor & cache version**: `config/hypr/scripts/generate-colors.sh` hardcodes monitor `DP-1` and awww version `0.12.1` in `~/.cache/awww/0.12.1/DP-1`. Changing the monitor port or upgrading awww breaks wallpaper path discovery.
  - **Matugen template divergence**: The active `~/.config/matugen/config.toml` and templates may contain `quickshell-colors.json`, `gtk3`, `gtk4`, `zen-colors`, and `obsidian` entries that are not tracked in the repo. Because `install.sh` symlinks the repo config/templates, those extra outputs disappear on a fresh deployment unless committed.
  - **Lua Configuration**: Hyprland uses the modern Lua API (`hl.config`, `hl.bind`, `hl.window_rule`, `hl.layer_rule`), not traditional `hyprland.conf` directives.
  - **Hybrid Brightness**: `brightness.sh` adjusts the internal display via `brightnessctl` and the external display via Quickshell IPC calling `services/BrightnessService.qml`, which throttles `ddcutil setvcp 10`.
  - **Hyprsunset Authority**: `services/HyprsunsetService.qml` queries `hyprctl hyprsunset identity get/temperature` and reconciles the live CTM every 30 seconds. Direct CLI changes are reverted to the bar state. The automatic schedule lives in Quickshell; native `hyprsunset.conf` profiles must stay disabled to avoid two planners.
  - **Sun Schedule Location**: The sunrise/sunset mode computes NOAA solar times from coordinates detected through `https://ipwho.is/` (`curl`, max 8 s) and cached in the state file for seven days. The refresh button in the popup forces a new lookup; without a cached location the service falls back to the saved manual filter state and disables the schedule toggle.
  - **Bar Frame Coupling**: The bar is a full-screen Top-layer surface whose input mask covers only the 30px bar strip (the whole surface while settings is open). The decorative frame is a separate full-screen Bottom-layer surface (`bar/Frame.qml`) with an empty input region; windows are composited above it, so their borders are never clipped by the rounded cut-out. `Dimensions.frame.thickness` must match Hyprland `gaps_out`, `Dimensions.frame.radius` must match `decoration.rounding + border_size`, and the frame path starts at `Dimensions.bar.height` because `Bar.qml` paints the strip above it.
  - **Volume Popup Focus**: `VolumePopup.qml` is a `PopupWindow` anchored to the volume pill and uses `HyprlandFocusGrab` to close on outside clicks; it is not a layer-shell namespace.
  - **MPRIS Workaround**: `NowPlaying.qml` sends raw `busctl` Play/Pause calls because some players (Firefox/Zen) report stale `PlaybackStatus`, which breaks Quickshell's `togglePlaying()`.
  - **Clipboard Watchers**: `ClipboardController.qml` starts one `wl-paste --watch` per MIME type through `scripts/cliphist-watch.sh` in a root `Scope`, so capture continues while the launcher is closed. Quickshell does not terminate `Quickshell.Io` children when it is killed; the wrapper terminates the identical watcher left behind by the previous shell (exact argv match in `/proc`) and only then execs `wl-paste`, so exactly one pair survives any number of restarts or QML reloads. Do not replace the wrapper with a plain `wl-paste` command, and do not move the controller back into `PanelWindow`.
  - **Audio Subscriber**: `AudioService.qml` starts its `pactl subscribe` listener through `scripts/pactl-subscribe.sh` for the same reason: the old listener survives a shell restart, and every restart used to add one more connected client to `pipewire-pulse`. That leak is what exhausts the server's client slots (`too many client application connections: Connection refused` in the user journal); `pactl` then exits 1 with empty stdout, which used to clear the device model and log `failed to parse` warnings. Keep the wrapper (exact argv `pactl subscribe` match, so one-shot `pactl list/get/set` calls are never touched) and do not run a second shell instance that also imports `AudioService`.
  - **Deferred Service Split**: `AudioParser.js`, `hyprsunset/Solar.js`, `hyprsunset/Schedule.js`, and `hyprsunset/StateStore.qml` are planned but not created. `AudioService.qml` and `HyprsunsetService.qml` still contain that logic inline; do not assume the subdirectories exist.
  - **Dead Window Rule**: In `hyprland.lua`, `hl.window_rule = { opacity = "0.95 0.7", blur = true, match = { class = "^(zen|-alpha|-browser)?$" } }` assigns a table to the API function instead of calling it, so no Zen rule is ever registered and `hl.window_rule` stays a table for the rest of the config (including `user.lua`, which loads after it). Confirmed live with `hyprctl eval 'error(type(hl.window_rule))'` → `TYPE=table` and `hyprctl eval 'hl.window_rule({...})'` → `attempt to call a table value (field 'window_rule')`. Use `hl.window_rule({...})` when it is fixed; note that window rules have no positive `blur` effect (only `no_blur`), and `hyprctl keyword` is rejected in Lua-config mode.

## 8. Open Questions
- Should `~/.config/matugen/templates/quickshell-colors.json` and the extra Matugen entries (GTK3/GTK4, Zen, Obsidian) be committed to `config/matugen/` so color generation is reproducible on a fresh checkout?
- Should the deferred `AudioParser.js`, `Solar.js`, `Schedule.js`, and `StateStore.qml` split be completed, or is the current inline service code the intended endpoint?
- Should the now-diagnosed dead `hl.window_rule = { ... }` block be corrected (and should the Zen match regex be fixed too), given that a mistake there can make the desktop unusable?
