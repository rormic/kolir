import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"
import "../../../theme"

// Cover-art palette for the now-playing island.
//
// Matugen derives primary_container / on_primary_container from the current
// track's mpris:artUrl in the helper (downloaded once per URL, then rendered
// with --dry-run so no template is written). Requests are debounced for a
// second and a superseded helper is stopped, so skipping tracks cannot spawn a
// chain of Matugen runs. Palettes are cached per URL in memory: pausing and
// resuming the same track applies the color again instantly.
//
// The view decides when the palette is live: `active` is false without a
// player or cover URL, and `paletteReady` then falls back to the regular
// Colors in NowPlaying.
Scope {
    id: root

    property string artUrl: ""
    property bool active: false

    property bool paletteReady: false
    property color containerColor: "transparent"
    property color containerTextColor: "transparent"
    property color accentColor: "transparent"
    property color accentTextColor: "transparent"

    // Palette changes crossfade like the rest of the shell instead of cutting.
    Behavior on containerColor {
        ColorAnimation { duration: Motion.theme; easing.type: Motion.themeEasing }
    }
    Behavior on containerTextColor {
        ColorAnimation { duration: Motion.theme; easing.type: Motion.themeEasing }
    }
    Behavior on accentColor {
        ColorAnimation { duration: Motion.theme; easing.type: Motion.themeEasing }
    }
    Behavior on accentTextColor {
        ColorAnimation { duration: Motion.theme; easing.type: Motion.themeEasing }
    }

    // URL the running helper was started for. A late answer from a previous
    // track is dropped by comparing it with `artUrl`.
    property string requestedUrl: ""
    // Set when a debounce fired while the previous helper was still running;
    // the next run starts as soon as it exits.
    property bool pendingRun: false
    // url -> { container, onContainer } for this shell session.
    property var palettes: ({})

    function sync() {
        if (!root.active || root.artUrl === "") {
            debounce.stop();
            paletteProc.running = false;
            root.requestedUrl = "";
            root.pendingRun = false;
            root.paletteReady = false;
            return;
        }

        // Cancel the previous track's helper immediately; the debounce below
        // only decides whether a new one is needed.
        if (paletteProc.running && root.requestedUrl !== root.artUrl) {
            root.pendingRun = false;
            paletteProc.running = false;
        }

        const cached = root.palettes[root.artUrl];
        if (cached) {
            debounce.stop();
            root.pendingRun = false;
            root.containerColor = cached.container;
            root.containerTextColor = cached.onContainer;
            root.accentColor = cached.accent || cached.onContainer;
            root.accentTextColor = cached.accentText || cached.container;
            root.paletteReady = true;
            return;
        }

        // Keep the previous palette during the debounce instead of flashing
        // the default colors between two tracks.
        debounce.restart();
    }

    function run() {
        if (!root.active || root.artUrl === "")
            return;

        // Never replace a live helper in the same tick: queue the request for
        // its exit handler so a killed run cannot report a false failure.
        if (paletteProc.running) {
            root.pendingRun = true;
            return;
        }

        root.pendingRun = false;
        root.requestedUrl = root.artUrl;
        paletteProc.command = [
            "python3",
            ShellPaths.nowPlayingColors,
            root.requestedUrl,
        ];
        paletteProc.running = true;
    }

    function apply(text) {
        if (!root.active || root.requestedUrl !== root.artUrl)
            return;

        const content = text.trim();
        if (content === "")
            return;

        try {
            const parsed = JSON.parse(content);
            const container = parsed.primary_container;
            const onContainer = parsed.on_primary_container;
            const primary = parsed.primary || onContainer;
            const onPrimary = parsed.on_primary || container;

            if (typeof container !== "string" || typeof onContainer !== "string")
                return;

            root.palettes[root.artUrl] = {
                container: container,
                onContainer: onContainer,
                accent: primary,
                accentText: onPrimary,
            };
            root.containerColor = container;
            root.containerTextColor = onContainer;
            root.accentColor = primary;
            root.accentTextColor = onPrimary;
            root.paletteReady = true;
        } catch (error) {
            console.warn("CoverPalette: invalid palette JSON:", error);
        }
    }

    onArtUrlChanged: sync()
    onActiveChanged: sync()

    Timer {
        id: debounce

        interval: 1000
        repeat: false
        onTriggered: root.run()
    }

    Process {
        id: paletteProc

        running: false

        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("CoverPalette:", text.trim());
            }
        }

        onExited: (code, status) => {
            if (root.pendingRun) {
                root.pendingRun = false;
                root.run();
                return;
            }

            if (!root.active || root.requestedUrl !== root.artUrl)
                return;

            if (code === 0)
                return;

            // No art, an unreachable URL or a Matugen failure: go back to the
            // theme colors instead of keeping a palette from another track.
            root.paletteReady = false;
            console.warn("CoverPalette: helper exited with code", code);
        }
    }

    Component.onCompleted: sync()
}
