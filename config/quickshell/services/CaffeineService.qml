pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// "Keep awake" toggle. While enabled, Bar.qml holds a Wayland idle inhibitor
// on the bar surface, so Hyprland never marks the session idle and hypridle
// skips all of its listeners (lock, DPMS off, suspend).
//
// The state lives in the runtime dir: a shell restart keeps a running timer,
// while a reboot clears it. `until` is an absolute epoch timestamp, so a
// countdown stays correct across suspend/resume.
QtObject {
    id: root

    property bool enabled: false
    // Epoch ms. 0 means "until the user turns it off".
    property real until: 0
    // 0 = indefinite, otherwise the preset that started the timer.
    property int presetMinutes: 0

    property date now: new Date()

    property bool stateLoaded: false
    property bool stateDirReady: false

    readonly property bool timed: root.enabled && root.until > 0
    readonly property int remainingSeconds: root.timed
        ? Math.max(0, Math.ceil((root.until - root.now.getTime()) / 1000))
        : 0

    // Compact label for the bar indicator.
    readonly property string shortLabel: {
        if (!root.timed)
            return "";

        const seconds = root.remainingSeconds;
        if (seconds < 60)
            return "<1m";

        const minutes = Math.ceil(seconds / 60);
        if (minutes < 60)
            return minutes + "m";

        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        return rest === 0 ? hours + "h" : hours + "h " + rest + "m";
    }

    readonly property string statusText: {
        if (!root.enabled)
            return "Off · normal idle timers";

        if (!root.timed)
            return "On · until you turn it off";

        return "On · " + Math.max(1, Math.ceil(root.remainingSeconds / 60))
            + " min left";
    }

    function enable(minutes) {
        const value = Math.max(0, Math.round(Number(minutes) || 0));

        root.presetMinutes = value;
        root.until = value > 0 ? Date.now() + value * 60000 : 0;
        root.now = new Date();
        root.enabled = true;
        root.saveState();
    }

    function disable() {
        root.enabled = false;
        root.until = 0;
        root.presetMinutes = 0;
        root.saveState();
    }

    function toggle() {
        if (root.enabled)
            root.disable();
        else
            root.enable(0);
    }

    function loadState() {
        const content = root.stateFile.text();
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);
                const until = Number(parsed.until) || 0;
                const preset = Math.max(0,
                    Math.round(Number(parsed.presetMinutes) || 0));

                if (parsed.enabled) {
                    root.enabled = true;
                    root.until = until;
                    root.presetMinutes = preset;
                }
            } catch (error) {
                console.warn("CaffeineService: invalid state file:", error);
            }
        }

        root.stateLoaded = true;

        // A timer that expired while the shell was down must not survive.
        if (root.enabled && root.until > 0 && root.until <= Date.now())
            root.disable();
    }

    function saveState() {
        if (!root.stateLoaded)
            return;

        root.saveTimer.restart();
    }

    function writeState() {
        if (!root.stateDirReady)
            return;

        root.stateFile.setText(JSON.stringify({
            enabled: root.enabled,
            until: root.enabled ? root.until : 0,
            presetMinutes: root.enabled ? root.presetMinutes : 0,
        }, null, 2));
    }

    property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.enabled
        triggeredOnStart: true

        onTriggered: {
            root.now = new Date();

            if (root.timed && root.now.getTime() >= root.until)
                root.disable();
        }
    }

    property Timer saveTimer: Timer {
        interval: 300
        repeat: false

        onTriggered: root.writeState()
    }

    // The recorder owns $XDG_RUNTIME_DIR/kolir, but it only creates it when a
    // recording starts. Make sure the directory exists and seed the state file
    // before FileView starts watching it, so the first load does not log a
    // "file does not exist" warning.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "caffeine", ShellPaths.runtimeStateDir, ShellPaths.caffeineState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("CaffeineService: cannot create",
                    ShellPaths.runtimeStateDir);
                root.stateLoaded = true;
                return;
            }

            root.stateDirReady = true;
        }
    }

    property FileView stateFile: FileView {
        path: root.stateDirReady ? ShellPaths.caffeineState : ""
        atomicWrites: true

        onLoaded: root.loadState()
        onLoadFailed: root.stateLoaded = true
    }

    property IpcHandler ipc: IpcHandler {
        target: "caffeine"

        function toggle(): void {
            root.toggle();
        }

        function enable(): void {
            root.enable(0);
        }

        function disable(): void {
            root.disable();
        }

        function setMinutes(minutes: string): void {
            root.enable(Number(minutes));
        }
    }
}
