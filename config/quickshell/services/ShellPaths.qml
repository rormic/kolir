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

    // Theme state shared with the Hyprland scripts.
    readonly property string currentTheme: home + "/.cache/current_theme"

    // Matugen-generated palette consumed by Colors.qml.
    readonly property string colorsJson: home + "/.config/quickshell/colors.json"

    // Night-light persistence owned by HyprsunsetService.
    readonly property string hyprsunsetState: home + "/.cache/quickshell/hyprsunset.json"

    // Runtime directory, falling back to /tmp when XDG_RUNTIME_DIR is unset.
    readonly property string runtimeDir: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return dir && dir.length > 0 ? dir : "/tmp";
    }

    // Recorder state watched by RecordingStatus.
    readonly property string recordingState: runtimeDir + "/kolir/recording.json"

    // Image previews generated for clipboard entries.
    readonly property string clipboardPreviewDir: "/tmp/qs-clip-previews"

    // Clipboard helpers bundled inside the shell config.
    readonly property string cliphistStore: Quickshell.shellPath("scripts/cliphist-store.py")
    readonly property string cliphistWatch: Quickshell.shellPath("scripts/cliphist-watch.sh")
    readonly property string cliphistPreviews: Quickshell.shellPath("scripts/cliphist-previews.py")

    // Audio helper bundled inside the shell config: keeps a single pactl
    // subscriber alive across shell restarts.
    readonly property string pactlSubscribe: Quickshell.shellPath("scripts/pactl-subscribe.sh")
}
