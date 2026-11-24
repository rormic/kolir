pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Screen frame style, chosen in Settings → Screen frame.
//
//   "ring"    — the classic full frame: the bar colour fills the window gaps
//               on all four sides and the desktop sits in a rounded cut-out.
//               This needs Hyprland's `general.gaps_out` to equal the frame
//               thickness (Dimensions.frame.thickness).
//   "corners" — only the four corner spandrels are painted; the upper two
//               share the bar colour and the lower two are black. The window
//               sides and bottom run flush to the screen edges, so that
//               variant needs no outer gaps at all.
//
// The state lives in ~/.cache/quickshell/frame.json. Frame.qml applies the
// matching `gaps_out` through Hyprland's Lua eval, so switching styles changes
// both the painted frame and the compositor spacing. hyprland.lua reads the
// same file at startup, so a restart starts directly in the saved style.
QtObject {
    id: root

    readonly property string ringStyle: "ring"
    readonly property string cornersStyle: "corners"

    // Every frame mode the selector can offer. Add a new entry here (plus its
    // rendering in Frame.qml and its drawing branch in FramePreview.qml) and
    // the Appearance card picks it up; the card deliberately renders one
    // visual preview per mode instead of a two-state switch.
    readonly property var styles: [
        {
            value: root.ringStyle,
            label: "Full frame",
            hint: "Border on all sides",
        },
        {
            value: root.cornersStyle,
            label: "Corner frame",
            hint: "Flush edges, black corners",
        },
    ]

    property string style: root.ringStyle

    // True once the cache directory exists, so a mode change can be written.
    property bool stateDirReady: false
    property bool writeQueued: false

    readonly property bool corners: root.style === root.cornersStyle

    function styleEntry(value) {
        for (let i = 0; i < root.styles.length; i++) {
            if (root.styles[i].value === value)
                return root.styles[i];
        }
        return null;
    }

    function labelFor(value) {
        const entry = root.styleEntry(value);
        return entry ? entry.label : value;
    }

    function hintFor(value) {
        const entry = root.styleEntry(value);
        return entry ? entry.hint : "";
    }

    function isStyle(value) {
        return root.styleEntry(value) !== null;
    }

    function setStyle(value) {
        if (!root.isStyle(value) || value === root.style)
            return;

        root.style = value;
        root.writeState();
    }

    // Cycle through the mode list. The IPC keeps a one-call shortcut; the
    // Appearance card sets a mode explicitly instead.
    function toggle() {
        if (root.styles.length === 0)
            return;

        let index = 0;
        for (let i = 0; i < root.styles.length; i++) {
            if (root.styles[i].value === root.style)
                index = i;
        }

        root.setStyle(root.styles[(index + 1) % root.styles.length].value);
    }

    // ── Persistence ────────────────────────────────────────────────────────
    function loadState(content) {
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);
                if (root.isStyle(parsed.style))
                    root.style = parsed.style;
            } catch (error) {
                console.warn("FrameService: invalid state file:", error);
            }
        }
    }

    function writeState() {
        if (!root.stateDirReady) {
            root.writeQueued = true;
            return;
        }

        root.writeQueued = false;
        root.stateFile.setText(JSON.stringify({
            style: root.style,
        }));
    }

    // Grow the cache directory and seed an empty state file once, so FileView
    // does not log a read failure on first run.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "frame", ShellPaths.quickshellCache, ShellPaths.frameState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("FrameService: cannot create",
                    ShellPaths.frameState);
                return;
            }

            root.stateDirReady = true;
            if (root.writeQueued)
                root.writeState();
        }
    }

    // blockLoading reads the saved style before the Frame singleton binds to
    // it, so a corner-only session never flashes the ring colours first.
    property FileView stateFile: FileView {
        path: ShellPaths.frameState
        blockLoading: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.loadState(this.text())
    }

    property IpcHandler ipc: IpcHandler {
        target: "frame"

        function setStyle(value: string): void {
            root.setStyle(value);
        }

        function toggle(): void {
            root.toggle();
        }

        function status(): string {
            return root.style;
        }
    }
}
