# kolir

A Material You desktop for Arch Linux on Wayland: Hyprland (Lua config) plus a
custom Quickshell bar, launcher, notifications, OSDs, and settings. Matugen
derives a neutral palette from the wallpaper and updates Hyprland, Foot,
GTK, and Quickshell.

**Phase 1:** install from a git checkout with `kolir setup`. There is no AUR
package yet, and the CLI never installs packages or writes outside your home
directory.

## Requirements

- Arch Linux with a Wayland session (Hyprland).
- Python 3.11+ (`python3` with `tomllib`) and `zsh`. `git` is only needed for a
  checkout (version reporting and updates); a package ships `.version`.
- The desktop stack: Hyprland, Quickshell, Matugen, awww, Foot, Hyprlock,
  Hypridle, Hyprsunset, brightnessctl, ddcutil, wl-clipboard, grim, slurp,
  libnotify, and wf-recorder for recording.
- Optional: `ffmpeg` (lock background), `cliphist` (clipboard history),
  NetworkManager (`nmcli`), BlueZ (`bluetoothctl`), `upower` (battery
  indicator on laptops), `python-dbus` + `python-gobject` (exact Bluetooth
  headset battery), `hyprpicker`, `wl-screenrec`, `zenity`, `nautilus`,
  `playerctl` (media keys), the `mocu-xcursor` theme, and KDE Connect.
- Fonts/icons used by the bar: Google Sans Code Nerd, DejaVu, Material Symbols,
  and Papirus.

`kolir doctor` reports missing required tools as errors and missing optional
tools as warnings. `kolir setup` offers to install the optional packages (and
`kolir setup --optional` does it unattended); required packages are never
installed by the CLI, because a checkout cannot know how your system is built.

## Install from a checkout

```sh
git clone https://github.com/ZaViBiS/kolir.git
cd kolir
tools/kolir.py setup          # or: ./bin/kolir setup
```

Until the phase-2 package installs `/usr/bin/kolir`, run the CLI as
`./bin/kolir` or `tools/kolir.py`; the examples below use `kolir` for brevity.

`setup` asks before changing anything, backs up every file/symlink it replaces
to `<path>.bak.YYYYmmdd-HHMMSS`, and is safe to re-run: a configured machine
reports "no changes".

Useful options:

| Option | Effect |
| --- | --- |
| `--dry-run` | Print every change without writing anything |
| `--force` | Recreate managed symlinks/files even when they look correct |
| `--yes` | Skip the confirmation and the interactive Obsidian question |
| `--zsh` | Link `~/.zshrc` and the `dice` Oh My Zsh theme (off by default) |
| `--obsidian PATH` | Enable Obsidian theming for a vault or an explicit `.css` file |
| `--obsidian-output FILE` | Enable Obsidian theming writing to `FILE` |
| `--no-obsidian` | Leave Obsidian theming untouched |
| `--auto-reload` | Install/enable the `kolir-reload` systemd user units |
| `--no-systemd` | Write the units but skip `systemctl` actions |
| `--optional` | Install the missing optional packages without asking |
| `--no-optional` | Do not offer to install the optional packages |

What it creates:

- Symlinks: `~/.config/hypr/{hyprland.lua,scripts,hyprsunset.conf,hyprlock.conf,hypridle.conf}`,
  `~/.config/mpv/mpv.conf`, `~/.config/matugen/hyprlock.toml`, and
  `~/.config/matugen/templates` when that path is absent.
- Copies only when absent: `~/.config/matugen/config.toml`,
  `~/.config/hypr/user.lua`, `~/.config/hypr/hyprlock-colors.conf`,
  `~/.config/quickshell/colors.json`, `~/.config/gtk-3.0/gtk.css`,
  `~/.config/gtk-4.0/gtk.css`, and `~/.cache/current_theme` (`dark`).
- A stable `~/.config/foot/foot.ini` loader plus an empty
  `~/.config/foot/colors.ini` (Matugen's output).
- `<root>/.version`, used by `kolir version` and the auto-reload unit.
- `~/Pictures/wallpaper`, the folder the wallpaper picker opens first.
- Enables `hypridle.service` (`systemctl --user enable --now`) unless
  `--no-systemd` is passed.
- Lists the optional packages that are still missing (`cliphist`, `ffmpeg`,
  `upower`, `hyprpicker`, `zenity`, KDE Connect, the `mocu-xcursor` theme, …)
  and asks whether to install them. Nothing is installed without an explicit
  "yes"; `--yes` leaves them alone, `--optional` installs them unattended, and
  `--no-optional` skips the question. `paru`/`yay` is used when present so the
  AUR-only `wl-screenrec`/`mocu-xcursor` resolve too, otherwise `pacman`
  handles the repository packages.

A real `~/.config/matugen/templates` directory is kept: missing shipped
templates are added as individual symlinks, and your files are never
overwritten. Obsidian has **no default vault path**; it is configured only when
you pass a path (or answer "yes" and enter one).

## First run

1. `kolir setup` creates `~/.config/hypr/user.lua` from the example if it is
   missing. If you already have one, replace its old `quickshell -p ...`
   autostart with `sh ~/.config/hypr/scripts/launch-shell.sh`; `kolir doctor`
   warns when the old path is still present. The example also starts
   `awww-daemon`.
2. Log in to Hyprland (or run `hyprctl reload` in an existing session).
3. Start or restart the shell with `kolir reload`, or start it directly with
   `kolir shell`.
4. Set a wallpaper with `SUPER+CTRL+ALT+T` (random) or `SUPER+CTRL+T` (picker)
   so Matugen can generate colors.
5. Run `kolir doctor` and fix any errors before reporting problems.

## Commands

```sh
kolir setup [options]     # create/refresh the per-user glue
kolir doctor              # check commands, links, generated files, Hyprland
kolir reload [--colors] [--no-shell]
                          # reload Hyprland + restart Quickshell; --colors
                          # regenerates the palette first
kolir shell [args...]     # exec qs -p <root>/config/quickshell
kolir ipc <target> <method> [args...]
                          # forward an IPC call to the running shell
kolir version             # .version, else git describe, else "unknown"
kolir uninstall-user [--dry-run]
                          # remove only glue that still points into <root>
```

`kolir` resolves `<root>` from `$KOLIR_ROOT`, then the checkout around the
script, then `/usr/share/kolir` (future package layout). The same resolution is
available to shell helpers through `config/hypr/scripts/lib/root.sh`.

## Update

```sh
cd /path/to/kolir
git pull
kolir reload
```

`kolir setup` only needs to be re-run after a root move or to pick up new
per-user glue (for example a new shipped Matugen template). With
`setup --auto-reload`, the user path unit watches `<root>/.version` and the
current git ref and runs `kolir reload` automatically; `--no-systemd` keeps the
units but skips `systemctl`.

An AUR package is planned for phase 2 and is **not available yet**. Until then,
the checkout is the installation.

## Uninstall

```sh
kolir uninstall-user --dry-run   # report first
kolir uninstall-user
```

This removes only symlinks/loaders/units that still point into the current
root. `user.lua`, the Matugen config and templates, generated colors,
`~/.cache/current_theme`, the GTK import stubs, and `~/.zshrc` are left in
place; timestamped `.bak.*` backups are never deleted automatically. Delete the
checkout itself when you are done.

## Credits

The shell, the scripts and the configuration were written for kolir. Other
Wayland and Quickshell setups were studied as architectural references.

The desktop itself is a set of separate programs (Hyprland, Quickshell,
Matugen, awww, Foot, …) with their own licenses and maintainers. They are not
bundled with kolir; see [THIRD-PARTY.md](THIRD-PARTY.md) for the full list.

## License

kolir is Copyright (C) 2025-2026 rormic and is licensed under the
**GNU General Public License, version 3 only** (`GPL-3.0-only`).
See [LICENSE](LICENSE) for the full text.

A small amount of third-party material is included: `zshrc` is derived from
the Oh My Zsh template (MIT), `config/hypr/hyprland.lua` from the Hyprland
example config (BSD-3-Clause), and `config/matugen/templates/obsidian.css` is a
verbatim copy of the Matugen themes template (MIT). Their notices are
reproduced in [THIRD-PARTY.md](THIRD-PARTY.md).
