pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// DDC/CI brightness control for the external display (VCP 0x10).
// The value is scaled to percent and kept in sync with the monitor.
QtObject {
    id: root

    property int rawValue: 100
    property int rawMax: 100
    property bool available: false
    property bool ready: false
    readonly property int value: rawMax > 0 ? Math.round(rawValue / rawMax * 100) : 0

    // Сигнал для OSD: значення яскравості змінилось (від користувача або монітора)
    signal brightnessChangedManually(int val)

    // Latest requested raw value while a ddcutil write is in flight.
    property int pendingRaw: -1
    property double lastLocalChange: 0

    function adjust(step) {
        if (!root.available)
            return;
        root.setValue(root.value + step);
    }

    function setValue(percent) {
        if (!root.available)
            return;

        const clamped = Math.max(0, Math.min(100, Math.round(percent)));
        if (clamped === root.value)
            return;

        const raw = Math.round(clamped / 100 * root.rawMax);
        root.rawValue = raw;
        root.pendingRaw = raw;
        root.lastLocalChange = Date.now();

        if (!writeProc.running)
            root.writePending();

        root.brightnessChangedManually(root.value);
    }

    function writePending() {
        if (root.pendingRaw < 0)
            return;

        const raw = root.pendingRaw;
        root.pendingRaw = -1;
        writeProc.exec(["ddcutil", "setvcp", "10", String(raw), "--sleep-multiplier", "0.1"]);
    }

    property Process readProc: Process {
        command: ["ddcutil", "getvcp", "10", "--brief", "--sleep-multiplier", "0.1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                // Format: VCP 10 C <current> <max>
                if (parts.length < 5 || parts[2] !== "C")
                    return;

                const current = parseInt(parts[3]);
                const max = parseInt(parts[4]);
                if (isNaN(current) || isNaN(max) || max <= 0)
                    return;

                const localChangeIsRecent = Date.now() - root.lastLocalChange < 1500;
                if (!writeProc.running && root.pendingRaw < 0 && !localChangeIsRecent) {
                    const previousValue = root.value;
                    root.rawMax = max;
                    root.rawValue = current;
                    if (root.ready && root.value !== previousValue)
                        root.brightnessChangedManually(root.value);
                }
                root.available = true;
                root.ready = true;
            }
        }
    }

    property Process writeProc: Process {
        running: false

        onExited: (exitCode, exitStatus) => {
            if (root.pendingRaw >= 0)
                root.writePending();
            else if (exitCode !== 0)
                console.warn("BrightnessService: ddcutil setvcp failed with code", exitCode);
        }
    }

    // Poll occasionally so changes made with the monitor buttons are picked up.
    property Timer refreshTimer: Timer {
        interval: 30000
        repeat: true
        running: true

        onTriggered: {
            if (!readProc.running && !writeProc.running && root.pendingRaw < 0)
                readProc.running = true;
        }
    }

    // Optional entry point for keyboard shortcuts: quickshell ipc call brightness up
    property IpcHandler ipc: IpcHandler {
        target: "brightness"

        function up(): void {
            root.adjust(5);
        }

        function down(): void {
            root.adjust(-5);
        }

        function set(percent: string): void {
            root.setValue(Number(percent));
        }
    }
}
