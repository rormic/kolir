pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Capture history: the newest screenshots and screen recordings from the two
// directories the Hyprland helpers write to. scripts/capture-history.sh does
// the scanning, sorting and cached ffmpeg posters; this service owns the model,
// the refresh cadence while the panel is open, and the card actions.
//
// Paths come from ShellPaths (which mirrors the scripts' KOLIR_SHOT_DIR /
// KOLIR_REC_DIR overrides), so nothing here builds a HOME path by hand.
QtObject {
    id: root

    // Roughly fifty cards keeps the grid to a few screens of scrolling.
    readonly property int limit: 50
    readonly property var sourceDirs: [ShellPaths.screenshotDir, ShellPaths.recordingsDir]

    // True while CaptureHistory is visible. The poll timer only runs then, so
    // a new recording or screenshot appears within a few seconds without a
    // shell restart, and a closed panel costs nothing.
    property bool active: false
    property bool scanning: false
    property int total: 0
    property int loaded: 0
    property string error: ""

    // Plain records; the grid reads them through the delegate's modelData.
    // A ListModel owned by a singleton does not hand per-key roles to a
    // delegate in another component, and required properties stay unset.
    property var entries: []
    readonly property int count: root.entries.length

    signal copied(string path, string kind)
    signal deleted(string path)
    signal openFailed(string path)
    signal actionFailed(string message)

    // Staging buffers the worker's stream so a model rebuild only happens when
    // the file set really changed. The panel keeps its selection otherwise.
    property var stagedEntries: []
    property string modelSignature: ""
    property bool restartPending: false

    property Timer watchTimer: Timer {
        interval: 5000
        repeat: true
        running: false
        onTriggered: root.refresh()
    }

    property Process scanProc: Process {
        running: false

        stdout: SplitParser {
            onRead: line => root.consumeLine(line)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Capture history:", message);
            }
        }

        onExited: code => {
            if (root.restartPending) {
                root.restartPending = false;
                root.scanning = false;
                if (root.active)
                    root.beginScan();
                return;
            }

            root.scanning = false;
            if (code !== 0 && root.stagedEntries.length === 0)
                root.error = "Could not read the capture folders";

            if (root.signature() !== root.modelSignature)
                root.rebuild();
        }
    }

    property Process copyProc: Process {
        property string targetPath: ""
        property string targetKind: ""

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Capture history: copy:", message);
            }
        }

        onExited: code => {
            if (code === 0)
                root.copied(copyProc.targetPath, copyProc.targetKind);
            else
                root.actionFailed(copyProc.targetKind === "video"
                    ? "Could not copy the path"
                    : "Could not copy the image");
        }
    }

    property Process openProc: Process {
        property string targetPath: ""

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Capture history: open:", message);
            }
        }

        onExited: code => {
            if (code !== 0)
                root.openFailed(openProc.targetPath);
        }
    }

    property Process removeProc: Process {
        property string targetPath: ""

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Capture history: delete:", message);
            }
        }

        onExited: code => {
            if (code === 0) {
                root.deleted(removeProc.targetPath);
                root.refresh();
            } else {
                root.actionFailed("Could not delete the file");
            }
        }
    }

    function setActive(value) {
        if (root.active === value)
            return;

        root.active = value;
        if (value) {
            root.refresh();
            root.watchTimer.restart();
        } else {
            root.watchTimer.stop();
            if (root.scanProc.running) {
                root.restartPending = true;
                root.scanProc.running = false;
            }
        }
    }

    function refresh() {
        if (root.scanProc.running) {
            root.restartPending = true;
            return;
        }
        root.beginScan();
    }

    function beginScan() {
        root.restartPending = false;
        root.stagedEntries = [];
        root.loaded = 0;
        root.error = "";
        root.scanning = true;
        root.scanProc.command = ["sh", ShellPaths.captureHistoryThumbnails,
            ShellPaths.capturePreviewDir, String(root.limit)].concat(root.sourceDirs);
        root.scanProc.running = true;
    }

    function consumeLine(line) {
        const parts = line.split("\t");

        if (parts[0] === "total") {
            root.total = Number(parts[1]) || 0;
            return;
        }

        if (parts.length < 4 || parts[0] === "")
            return;

        root.stagedEntries.push({
            path: parts[0],
            thumb: parts[1] || "",
            kind: parts[2] === "video" ? "video" : "image",
            mtime: Number(parts[3]) || 0,
        });
        root.loaded = root.stagedEntries.length;
    }

    function signature() {
        return root.stagedEntries.map(entry => entry.path + "\t" + entry.mtime).join("\n");
    }

    function rebuild() {
        root.entries = root.stagedEntries.slice();
        root.modelSignature = root.signature();
    }

    function mimeFor(path) {
        const dot = path.lastIndexOf(".");
        const extension = dot >= 0 ? path.substring(dot + 1).toLowerCase() : "";

        switch (extension) {
        case "jpg":
        case "jpeg":
            return "image/jpeg";
        case "webp":
            return "image/webp";
        case "gif":
            return "image/gif";
        default:
            return "image/png";
        }
    }

    // Images go to the clipboard as a real image; a recording has no useful
    // image representation, so its absolute path is copied instead.
    function copy(path, kind) {
        if (path === "" || root.copyProc.running)
            return;

        root.copyProc.targetPath = path;
        root.copyProc.targetKind = kind;
        root.copyProc.command = kind === "video"
            ? ["wl-copy", path]
            : ["sh", "-c", 'exec wl-copy -t "$2" < "$1"',
                "kolir-capture-copy", path, root.mimeFor(path)];
        root.copyProc.running = true;
    }

    function open(path) {
        if (path === "" || root.openProc.running)
            return;

        root.openProc.targetPath = path;
        root.openProc.command = ["xdg-open", path];
        root.openProc.running = true;
    }

    function remove(path) {
        if (path === "" || root.removeProc.running)
            return;

        root.removeProc.targetPath = path;
        root.removeProc.command = ["rm", "-f", "--", path];
        root.removeProc.running = true;
    }
}
