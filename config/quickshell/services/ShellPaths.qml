pragma Singleton
import QtQuick
import Quickshell

// Single source of truth for every path that points outside the shell config:
// Hyprland helper scripts, generated theme state, runtime state and the
// external helper scripts bundled with the shell. Consumers must not build
// these paths from HOME themselves.
QtObject {
    readonly property string home: Quickshell.env("HOME")

    // Hyprland helper scripts installed under ~/.config/hypr/scripts.
    readonly property string hyprScripts: home + "/.config/hypr/scripts"

    // SMBIOS chassis type, used by BatteryService to tell a laptop (where a
    // missing battery is a problem) from a desktop (where it is normal).
    readonly property string chassisType: "/sys/class/dmi/id/chassis_type"

    // Theme state shared with the Hyprland scripts.
    readonly property string currentTheme: home + "/.cache/current_theme"

    // Bluetooth headset battery helper bundled with the shell, plus the cache
    // it uses to avoid reconnecting to an exact-protocol device every minute.
    readonly property string deviceBatteryScript: Quickshell.shellPath("scripts/device-battery/main.py")
    readonly property string deviceBatteryState: home + "/.cache/quickshell/device-battery.json"

    // Quickshell cache directory shared by the persisted UI state files.
    readonly property string quickshellCache: home + "/.cache/quickshell"

    // Notification center history and DND state owned by NotificationService.
    readonly property string notificationState: quickshellCache + "/notifications.json"

    // Calendar events owned by CalendarService (local backend for now).
    readonly property string calendarState: quickshellCache + "/calendar.json"

    // Event sound helper bundled with the shell. EventSoundService runs it for
    // notification, USB and low-battery chimes; the event name selects the
    // freedesktop sound and the optional second argument overrides the file.
    readonly property string eventSound: Quickshell.shellPath("scripts/event-sound.sh")

    // USB attach listener bundled with the shell. Its wrapper stops the monitor
    // left behind by a previous shell before starting a new one.
    readonly property string usbWatch: Quickshell.shellPath("scripts/usb-watch.sh")

    // Matugen-generated palette consumed by Colors.qml.
    readonly property string colorsJson: home + "/.config/quickshell/colors.json"

    // Matugen scheme type, contrast and mode owned by AppearanceService.
    readonly property string appearanceState: quickshellCache + "/appearance.json"

    // Screen frame style owned by FrameService.
    readonly property string frameState: quickshellCache + "/frame.json"

    // Night-light persistence owned by HyprsunsetService.
    readonly property string hyprsunsetState: home + "/.cache/quickshell/hyprsunset.json"

    // Runtime directory, falling back to /tmp when XDG_RUNTIME_DIR is unset.
    readonly property string runtimeDir: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return dir && dir.length > 0 ? dir : "/tmp";
    }

    // Ephemeral session state shared with the Hyprland helper scripts.
    readonly property string runtimeStateDir: runtimeDir + "/kolir"

    // Recorder state watched by RecordingStatus.
    readonly property string recordingState: runtimeStateDir + "/recording.json"

    // Keep-awake state owned by CaffeineService.
    readonly property string caffeineState: runtimeStateDir + "/caffeine.json"

    // Image previews generated for clipboard entries.
    readonly property string clipboardPreviewDir: "/tmp/qs-clip-previews"

    // Screenshot library written by screenshot-region.sh. KOLIR_SHOT_DIR is
    // the same override the script honours.
    readonly property string screenshotDir: {
        const dir = Quickshell.env("KOLIR_SHOT_DIR");
        return dir && dir.length > 0 ? dir : home + "/Pictures/Screenshots";
    }

    // Screen recordings written by screen-record.sh. KOLIR_REC_DIR is the same
    // override the script honours.
    readonly property string recordingsDir: {
        const dir = Quickshell.env("KOLIR_REC_DIR");
        return dir && dir.length > 0 ? dir : home + "/Videos/Recordings";
    }

    // Capture-history worker and its 16:9 poster cache.
    readonly property string captureHistoryThumbnails: Quickshell.shellPath("scripts/capture-history.sh")
    readonly property string capturePreviewDir: quickshellCache + "/capture-previews"

    // Wallpaper library shared with select-wallpaper.sh/random-wallpaper.sh.
    readonly property string wallpaperDir: home + "/Pictures/wallpaper"

    // Active wallpaper engine and the last path of each kind. Written by
    // set-wallpaper.sh/wallpaper-backend.sh, read by WallpaperService.
    //   {"backend":"awww","image":"/…/a.jpg","video":"/…/b.mp4"}
    readonly property string wallpaperState: quickshellCache + "/wallpaper.json"

    // Clipboard helpers bundled inside the shell config.
    readonly property string cliphistStore: Quickshell.shellPath("scripts/cliphist-store.py")
    readonly property string cliphistWatch: Quickshell.shellPath("scripts/cliphist-watch.sh")
    readonly property string cliphistPreviews: Quickshell.shellPath("scripts/cliphist-previews.py")

    // Per-scheme palette previews for the Appearance page.
    readonly property string palettePreviews: Quickshell.shellPath("scripts/palette-previews.sh")
    readonly property string palettePreviewsCache: quickshellCache + "/palette-previews.json"

    // Now-playing cover palette helper. It caches the downloaded art and runs
    // Matugen with --dry-run, so only the island colors change.
    readonly property string nowPlayingColors: Quickshell.shellPath("scripts/now-playing-colors.py")

    // Directory suggestions for the picker's path field.
    readonly property string completeDirs: Quickshell.shellPath("scripts/complete-dirs.sh")

    // Generic one-directory listing for the picker.
    readonly property string listFiles: Quickshell.shellPath("scripts/list-files.sh")

    // Recursive name search used by the picker's search field.
    readonly property string searchFiles: Quickshell.shellPath("scripts/search-files.sh")

    // One-shot 16:9 poster helper for the picker. The picker runs it only for
    // tiles that become visible, so a huge photo folder never pre-generates
    // every thumbnail.
    readonly property string fileThumbnail: Quickshell.shellPath("scripts/file-thumbnail.sh")

    // Posters generated by file-thumbnail.sh. Kept in the Quickshell cache so
    // the grid never decodes full-size images. Not Quickshell.cachePath(): that
    // nests under a per-shell id directory, while an explicit path keeps one
    // predictable cache for every shell.
    readonly property string filePreviewDir: home + "/.cache/quickshell/file-previews"

    // Audio helper bundled inside the shell config: keeps a single pactl
    // subscriber alive across shell restarts.
    readonly property string pactlSubscribe: Quickshell.shellPath("scripts/pactl-subscribe.sh")

    // Obsidian quick-note helper bundled inside the shell config: resolves the
    // vault/daily note and appends the typed text (see launcher note mode).
    readonly property string quickNoteScript: Quickshell.shellPath("scripts/quick-note.py")
}
