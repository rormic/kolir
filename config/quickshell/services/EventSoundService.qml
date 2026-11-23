pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Short event sounds for the shell: a new notification, a USB device being
// attached and a low battery. scripts/event-sound.sh owns player selection
// (pw-play/paplay with the freedesktop theme files, canberra as the last
// resort), so this service only decides which event to play and when.
//
// One Process and one debounce timer keep a burst from spawning parallel
// players: the last event of a burst wins, and an event that arrives while the
// player is busy is queued once instead of dropped.
//
// Do-not-disturb silences arrivals (notification and USB) but not the low
// battery warning, which is a safety message rather than an interruption.
// NotificationService mirrors its DND state into `muted`.
QtObject {
    id: root

    property bool muted: false

    readonly property int debounceInterval: 200

    property string pendingEvent: ""
    property string pendingFile: ""
    property string queuedEvent: ""
    property string queuedFile: ""
    property bool hasQueued: false

    // A USB device record is only announced once, on its usb_device node. The
    // following usb_interface records (up to one per endpoint group) share the
    // same ACTION=add line and must stay silent.
    property bool usbAddRecord: false

    property Timer debounce: Timer {
        interval: root.debounceInterval
        repeat: false

        onTriggered: root.flush()
    }

    property Process player: Process {
        running: false

        onExited: root.playQueued()
    }

    // The udev listener bundled with the shell. Its wrapper stops the monitor
    // left behind by a previous shell before starting a new one.
    property Process usbWatcher: Process {
        command: [ShellPaths.usbWatch]
        running: true

        stdout: SplitParser {
            onRead: line => root.handleUdevLine(line)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("EventSoundService: usb-watch:", message);
            }
        }
    }

    // BatteryService emits one signal per crossed warning threshold, so this
    // service stays free of percentage arithmetic.
    property Connections battery: Connections {
        target: BatteryService

        function onLowBattery(threshold) {
            root.play(threshold <= 5 ? "battery-critical" : "battery-low");
        }
    }

    function playNotification(hintFile) {
        root.play("notification", hintFile);
    }

    function playUsb() {
        root.play("usb");
    }

    function play(event, file) {
        if (root.muted && event !== "battery-low" && event !== "battery-critical")
            return;

        root.pendingEvent = event;
        root.pendingFile = file ? String(file) : "";
        root.debounce.restart();
    }

    function flush() {
        if (root.pendingEvent === "")
            return;

        if (root.player.running) {
            root.queuedEvent = root.pendingEvent;
            root.queuedFile = root.pendingFile;
            root.hasQueued = true;
            return;
        }

        root.start(root.pendingEvent, root.pendingFile);
    }

    function playQueued() {
        if (!root.hasQueued)
            return;

        root.hasQueued = false;
        root.start(root.queuedEvent, root.queuedFile);
    }

    function start(event, file) {
        if (event === "")
            return;

        root.player.command = file === ""
            ? [ShellPaths.eventSound, event]
            : [ShellPaths.eventSound, event, file];
        root.player.running = true;
    }

    function handleUdevLine(line) {
        if (line.startsWith("ACTION=")) {
            root.usbAddRecord = line === "ACTION=add";
            return;
        }

        if (!line.startsWith("DEVTYPE="))
            return;

        if (root.usbAddRecord && line === "DEVTYPE=usb_device")
            root.playUsb();

        root.usbAddRecord = false;
    }
}
