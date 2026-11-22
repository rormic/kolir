pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Brightness control for the bar chip, the OSD and the brightness keys.
//
// Two backends are driven together, matching the old split between
// brightness.sh (internal panel) and this service (external monitor):
//   * the internal panel through brightnessctl (backlight class device)
//   * an external display through ddcutil (VCP 0x10)
//
// The chip and the OSD show the external display when DDC/CI answers and the
// internal panel otherwise. Laptops whose panel does not implement DDC/CI
// therefore get a working brightness chip instead of a hidden one.
QtObject {
    id: root

    // Internal panel (brightnessctl).
    property int internalRaw: 0
    property int internalMax: 0
    property bool internalAvailable: false
    property bool internalReady: false

    // External display (ddcutil VCP 0x10).
    property int externalRaw: 100
    property int externalMax: 100
    property bool externalAvailable: false
    property bool externalReady: false

    readonly property bool available: root.internalAvailable || root.externalAvailable
    readonly property bool ready: root.internalReady || root.externalReady

    readonly property int internalValue: root.percentOf(root.internalRaw, root.internalMax)
    readonly property int externalValue: root.percentOf(root.externalRaw, root.externalMax)

    // DDC/CI wins when it answers so desktops keep the monitor readout and the
    // monitor buttons stay authoritative; the internal panel is the fallback.
    readonly property int value: root.externalAvailable ? root.externalValue : root.internalValue

    // Emitted once per user-visible adjustment, whether it came from the bar,
    // the IPC handlers or the brightness keys. BrightnessOsd listens to it.
    signal brightnessChangedManually(int val)

    // Latest requested raw value while a write is in flight. Writes are
    // coalesced so holding a brightness key does not spawn one process per
    // repeat event.
    property int pendingInternalRaw: -1
    property int pendingExternalRaw: -1
    property double lastInternalChange: 0
    property double lastExternalChange: 0

    function percentOf(raw, max) {
        return max > 0 ? Math.round(raw / max * 100) : 0;
    }

    function clampPercent(percent) {
        return Math.max(0, Math.min(100, Math.round(percent)));
    }

    // Relative step: every available backend moves by `step` percent of its
    // own range, so a laptop keeps controlling its panel while a DDC/CI
    // monitor next to it follows along (the pre-service hybrid behaviour).
    function adjust(step) {
        if (!root.available)
            return;

        const previousInternal = root.internalValue;
        const previousExternal = root.externalValue;

        if (root.internalAvailable)
            root.applyInternal(previousInternal + step);
        if (root.externalAvailable)
            root.applyExternal(previousExternal + step);

        if (root.internalValue !== previousInternal || root.externalValue !== previousExternal)
            root.brightnessChangedManually(root.value);
    }

    // Absolute value for the IPC `set` method: one number for the whole setup.
    function setValue(percent) {
        const numeric = Number(percent);
        if (!root.available || isNaN(numeric))
            return;

        const previousInternal = root.internalValue;
        const previousExternal = root.externalValue;
        const clamped = root.clampPercent(numeric);

        if (root.internalAvailable)
            root.applyInternal(clamped);
        if (root.externalAvailable)
            root.applyExternal(clamped);

        if (root.internalValue !== previousInternal || root.externalValue !== previousExternal)
            root.brightnessChangedManually(root.value);
    }

    function applyInternal(percent) {
        if (!root.internalAvailable)
            return;

        const raw = Math.round(root.clampPercent(percent) / 100 * root.internalMax);
        if (raw === root.internalRaw && root.pendingInternalRaw < 0)
            return;

        root.internalRaw = raw;
        root.pendingInternalRaw = raw;
        root.lastInternalChange = Date.now();

        if (!root.internalWriteProc.running)
            root.writeInternal();
    }

    function applyExternal(percent) {
        if (!root.externalAvailable)
            return;

        const raw = Math.round(root.clampPercent(percent) / 100 * root.externalMax);
        if (raw === root.externalRaw && root.pendingExternalRaw < 0)
            return;

        root.externalRaw = raw;
        root.pendingExternalRaw = raw;
        root.lastExternalChange = Date.now();

        if (!root.externalWriteProc.running)
            root.writeExternal();
    }

    function writeInternal() {
        if (root.pendingInternalRaw < 0)
            return;

        const raw = root.pendingInternalRaw;
        root.pendingInternalRaw = -1;
        root.internalWriteProc.exec(["brightnessctl", "-q", "-n2", "set", String(raw)]);
    }

    function writeExternal() {
        if (root.pendingExternalRaw < 0)
            return;

        const raw = root.pendingExternalRaw;
        root.pendingExternalRaw = -1;
        root.externalWriteProc.exec(["ddcutil", "setvcp", "10", String(raw), "--sleep-multiplier", "0.1"]);
    }

    function refresh() {
        if (!root.internalReadProc.running && !root.internalWriteProc.running && root.pendingInternalRaw < 0)
            root.internalReadProc.running = true;
        if (!root.externalReadProc.running && !root.externalWriteProc.running && root.pendingExternalRaw < 0)
            root.externalReadProc.running = true;
    }

    // `-c backlight` keeps keyboard LEDs out of the picture: without it,
    // brightnessctl falls back to the first device it finds (usually an LED).
    property Process internalReadProc: Process {
        command: ["brightnessctl", "-m", "-c", "backlight"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim().split("\n")[0];
                const parts = line ? line.split(",") : [];
                // Format: <device>,backlight,<current>,<percent%>,<max>
                if (parts.length < 5)
                    return;

                const current = parseInt(parts[2]);
                const max = parseInt(parts[4]);
                if (isNaN(current) || isNaN(max) || max <= 0)
                    return;

                const wasReady = root.internalReady;
                const previousValue = root.internalValue;

                root.internalMax = max;
                const localChangeIsRecent = Date.now() - root.lastInternalChange < 1500;
                if (!root.internalWriteProc.running && root.pendingInternalRaw < 0 && !localChangeIsRecent)
                    root.internalRaw = current;
                root.internalAvailable = true;
                root.internalReady = true;

                // Only the backend currently shown by the chip may raise the
                // OSD; a panel change while the external display is primary
                // stays silent.
                if (wasReady && !root.externalAvailable && root.internalValue !== previousValue)
                    root.brightnessChangedManually(root.internalValue);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;

            // A desktop without a backlight class device is a normal setup;
            // only report a failure that hides an already working chip.
            if (root.internalAvailable) {
                root.internalAvailable = false;
                console.warn("BrightnessService: brightnessctl read failed with code", exitCode);
            }
        }
    }

    property Process internalWriteProc: Process {
        running: false

        onExited: (exitCode, exitStatus) => {
            if (root.pendingInternalRaw >= 0)
                root.writeInternal();
            else if (exitCode !== 0)
                console.warn("BrightnessService: brightnessctl set failed with code", exitCode);
        }
    }

    property Process externalReadProc: Process {
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

                const wasReady = root.externalReady;
                const previousValue = root.externalValue;

                root.externalMax = max;
                const localChangeIsRecent = Date.now() - root.lastExternalChange < 1500;
                if (!root.externalWriteProc.running && root.pendingExternalRaw < 0 && !localChangeIsRecent)
                    root.externalRaw = current;
                root.externalAvailable = true;
                root.externalReady = true;

                if (wasReady && root.externalValue !== previousValue)
                    root.brightnessChangedManually(root.externalValue);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;

            if (root.externalAvailable) {
                root.externalAvailable = false;
                console.warn("BrightnessService: ddcutil getvcp failed with code", exitCode);
            }
        }
    }

    property Process externalWriteProc: Process {
        running: false

        onExited: (exitCode, exitStatus) => {
            if (root.pendingExternalRaw >= 0)
                root.writeExternal();
            else if (exitCode !== 0)
                console.warn("BrightnessService: ddcutil setvcp failed with code", exitCode);
        }
    }

    // Poll occasionally so changes made with the monitor buttons or another
    // brightness tool are picked up. While no backend answers (shell start,
    // monitor waking up) retry faster so the chip returns quickly.
    property Timer refreshTimer: Timer {
        interval: root.available ? 30000 : 5000
        repeat: true
        running: true

        onTriggered: root.refresh()
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
