pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Wallpaper engine choice and the last applied file of each kind.
//
// ~/.cache/quickshell/wallpaper.json is owned by set-wallpaper.sh and
// wallpaper-backend.sh, which also start/stop mpvpaper. This service only
// reads it (and reloads it on every write) and relays a switch to the script,
// so the picker and the shell scripts can never disagree:
//   {"backend":"awww","image":"/…/a.jpg","video":"/…/b.mp4"}
//
// At shell start `restore()` replays the video backend. The script is
// idempotent: it leaves a live mpvpaper playing the same file untouched, but
// starts the last video again after a logout or a crash killed the player.
// awww restores its own cache, so the image backend needs no call.
QtObject {
    id: root

    readonly property var backends: [
        { value: "awww", label: "Images" },
        { value: "mpvpaper", label: "Videos" },
    ]

    // Active engine as persisted by the scripts. Optimistically updated while
    // a switch is running and rolled back if the script fails.
    property string backend: "awww"
    property string imagePath: ""
    property string videoPath: ""
    property bool loaded: false
    property bool switching: false
    // Set on the first load when the saved state is a video; a user switch
    // before the restore timer fires cancels it.
    property bool restorePending: false
    // Backend to restore if the switch script fails.
    property string previousBackend: "awww"

    function labelFor(value) {
        for (let i = 0; i < root.backends.length; i++) {
            if (root.backends[i].value === value)
                return root.backends[i].label;
        }
        return "";
    }

    // Persists the choice and switches the engine. Selecting the active
    // backend is a no-op.
    function setBackend(value) {
        if (value !== "awww" && value !== "mpvpaper")
            return;
        if (root.switching || value === root.backend)
            return;

        root.previousBackend = root.backend;
        root.restorePending = false;
        root.backend = value;
        root.switching = true;
        switchProc.command = [
            "sh", ShellPaths.hyprScripts + "/wallpaper-backend.sh", value,
        ];
        switchProc.running = true;
    }

    function restore() {
        if (!root.restorePending || root.switching)
            return;
        root.restorePending = false;
        if (root.backend !== "mpvpaper" || root.videoPath === "")
            return;
        restoreProc.command = [
            "sh", ShellPaths.hyprScripts + "/wallpaper-backend.sh", "mpvpaper",
        ];
        restoreProc.running = true;
    }

    // Compact one-line state written by the scripts. A missing file means a
    // fresh machine and the historical awww default.
    property FileView stateView: FileView {
        path: ShellPaths.wallpaperState
        watchChanges: true

        onFileChanged: this.reload()

        onLoaded: {
            try {
                const parsed = JSON.parse(this.text());
                if (!parsed || typeof parsed !== "object")
                    return;

                root.backend = parsed.backend === "mpvpaper" ? "mpvpaper" : "awww";
                root.imagePath = typeof parsed.image === "string" ? parsed.image : "";
                root.videoPath = typeof parsed.video === "string" ? parsed.video : "";

                if (!root.loaded) {
                    root.loaded = true;
                    if (root.backend === "mpvpaper" && root.videoPath !== "") {
                        root.restorePending = true;
                        root.restoreTimer.restart();
                    }
                }
            } catch (error) {
                console.warn("WallpaperService: could not parse",
                    ShellPaths.wallpaperState, error);
            }
        }

        onLoadFailed: {
            if (!root.loaded) {
                root.loaded = true;
                root.backend = "awww";
            }
        }
    }

    // Let the session finish mapping its outputs before replaying a video; on
    // a normal shell restart restoreProc is a no-op, so the delay is harmless.
    property Timer restoreTimer: Timer {
        interval: 900
        repeat: false
        onTriggered: root.restore()
    }

    property Process switchProc: Process {
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("WallpaperService:", message);
            }
        }

        onExited: code => {
            if (code !== 0) {
                root.switching = false;
                root.backend = root.previousBackend;
                console.warn("WallpaperService: switching the backend failed, exit code", code);
                root.stateView.reload();
                return;
            }

            // The engine changed, so the palette must follow: regenerate from
            // the newly active wallpaper (a video is sampled to a frame).
            // `switching` stays true until this finishes, which keeps a second
            // chip click from overlapping two Matugen runs. A backend with no
            // file yet (first run of the Images/Videos grid) has nothing to
            // sample, so it keeps the current palette instead of failing.
            root.stateView.reload();
            if (root.backend === "awww" && root.imagePath === "") {
                root.switching = false;
                return;
            }
            if (root.backend === "mpvpaper" && root.videoPath === "") {
                root.switching = false;
                return;
            }
            root.colorsProc.running = true;
        }
    }

    property Process colorsProc: Process {
        running: false
        command: ["zsh", ShellPaths.hyprScripts + "/generate-colors.sh"]

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("WallpaperService:", message);
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("WallpaperService: generate-colors.sh failed, exit code", code);
            root.switching = false;
        }
    }

    property Process restoreProc: Process {
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("WallpaperService: restore:", message);
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("WallpaperService: restoring the video wallpaper failed, exit code", code);
        }
    }
}
