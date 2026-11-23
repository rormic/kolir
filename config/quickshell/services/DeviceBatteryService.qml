pragma Singleton
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import "."

// Battery levels of connected Bluetooth audio devices.
//
// A small Python helper asks each connected headset through a provider chain:
// brand protocols first (Sony MDR gives the live 1% value), then the generic
// BlueZ battery property. The helper prints a JSON array; this service only
// validates it and exposes the first device for the bar.
//
// The feature is deliberately quiet: with no connected headset, no supported
// provider, no Bluetooth adapter or no python-dbus the helper prints `[]`, the
// device list stays empty and the bar chip does not exist. There is no OSD and
// no notification. Polling is a short-lived process once a minute; the helper
// caches exact readings for a few minutes so it does not reconnect constantly,
// and reports `cached`/`stale`/`age` so the UI can say when a value was reused
// instead of just read.
QtObject {
    id: root

    // [{ address, name, percent, charging, source, exact, cached, stale, age }],
    // best source first.
    property var devices: []

    property bool reading: false
    property bool pending: false
    property bool pendingForce: false
    property bool queuedForce: false
    property bool forceRead: false
    property bool watchPrimed: false
    property bool warned: false

    readonly property var primary: root.devices.length > 0 ? root.devices[0] : null
    readonly property bool available: root.primary !== null
    readonly property int percentage: root.primary ? root.primary.percent : 0
    readonly property bool charging: root.primary ? root.primary.charging : false
    readonly property bool low: root.available && !root.charging && root.percentage <= 15
    readonly property string deviceName: root.primary ? root.primary.name : ""
    // The level was reused from the helper's cache instead of read from the
    // headset. `stale` means the device did not answer, so this is the last
    // known sample rather than a fresh cache window.
    readonly property bool stale: root.primary ? root.primary.stale === true : false
    readonly property bool cached: root.primary ? root.primary.cached === true : false
    readonly property int age: root.primary ? root.primary.age : 0

    function refresh(force) {
        if (root.reading) {
            root.pending = true;
            root.pendingForce = root.pendingForce || force === true;
            return;
        }

        root.forceRead = force === true;
        root.reading = true;
        root.reader.running = true;
    }

    function apply(text) {
        const raw = text.trim();
        if (raw === "")
            return;

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (error) {
            if (!root.warned) {
                console.warn("DeviceBatteryService: invalid helper output:", error);
                root.warned = true;
            }
            return;
        }
        if (!Array.isArray(parsed))
            return;

        const clean = [];
        for (let index = 0; index < parsed.length; index++) {
            const entry = parsed[index];
            if (!entry || typeof entry !== "object")
                continue;

            const percent = Math.round(Number(entry.percent));
            if (!isFinite(percent) || percent < 0 || percent > 100)
                continue;

            const age = Math.round(Number(entry.age));
            clean.push({
                address: typeof entry.address === "string" ? entry.address : "",
                name: typeof entry.name === "string" && entry.name !== ""
                    ? entry.name
                    : "Bluetooth device",
                percent: percent,
                charging: entry.charging === true,
                source: typeof entry.source === "string" ? entry.source : "",
                exact: entry.exact === true,
                cached: entry.cached === true,
                stale: entry.stale === true,
                age: isFinite(age) && age > 0 ? age : 0,
            });
        }

        root.devices = clean;
    }

    // One poll a minute. The helper is fast while its exact reading is fresh,
    // and a connect/disconnect shows up within one interval.
    property Timer poll: Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    property Timer rerun: Timer {
        interval: 50
        repeat: false

        onTriggered: {
            const force = root.queuedForce;
            root.queuedForce = false;
            root.refresh(force);
        }
    }

    // A newly connected headset must not show the level cached for its previous
    // session, so a connect event forces a live protocol read. The helper also
    // drops a device's cache when the previous run did not see it connected,
    // which covers a reconnect that happened between two polls.
    //
    // A one-second snapshot rather than a binding on the model members: a
    // binding on `Bluetooth.devices.values[i].connected` did not re-evaluate
    // on a real reconnect, and polling a list of a few devices once a second
    // costs nothing next to the once-a-minute helper.
    property var connectedAudio: []

    function audioAddresses() {
        const addresses = [];
        const devices = Bluetooth.devices.values;
        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (!device.connected)
                continue;
            if (!String(device.icon || "").startsWith("audio-"))
                continue;
            addresses.push(String(device.address || "").toUpperCase());
        }
        addresses.sort();
        return addresses;
    }

    property Timer connectionWatch: Timer {
        interval: 1000
        repeat: true
        running: true

        onTriggered: {
            const addresses = root.audioAddresses();
            const primed = root.watchPrimed;
            root.watchPrimed = true;

            if (addresses.join("\n") === root.connectedAudio.join("\n"))
                return;

            let appeared = false;
            for (let index = 0; index < addresses.length; index++) {
                if (root.connectedAudio.indexOf(addresses[index]) < 0) {
                    appeared = true;
                    break;
                }
            }
            root.connectedAudio = addresses;
            root.refresh(appeared);

            // The first read can arrive while BlueZ is still finishing the
            // connection, fail, and fall back to the device's previous level;
            // one delayed retry usually lands on a live value.
            if (appeared && primed)
                root.connectRetry.restart();
        }
    }

    property Timer connectRetry: Timer {
        interval: 6000
        repeat: false

        onTriggered: root.refresh(true)
    }

    // Quickshell does not kill a child that stops making progress, and this
    // service only starts a new poll once the previous one exits. A helper that
    // hangs (for example in a D-Bus call the protocol deadline did not cover)
    // would therefore freeze the chip until the shell restarts.
    property Timer watchdog: Timer {
        interval: 25000
        repeat: false
        running: root.reading

        onTriggered: {
            if (root.reader.running) {
                console.warn("DeviceBatteryService: helper timed out, killing it");
                root.reader.signal(9);
                return;
            }

            // The process never started (for example python3 is missing), so
            // no exited signal is coming.
            root.reading = false;
            if (root.pending) {
                root.pending = false;
                root.queuedForce = root.pendingForce;
                root.pendingForce = false;
                root.rerun.restart();
            }
        }
    }

    property Process reader: Process {
        command: [
            "python3",
            ShellPaths.deviceBatteryScript,
            "--state", ShellPaths.deviceBatteryState,
        ].concat(root.forceRead ? ["--force"] : [])
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }

        onExited: (exitCode, exitStatus) => {
            root.reading = false;
            if (root.pending) {
                root.pending = false;
                root.queuedForce = root.pendingForce;
                root.pendingForce = false;
                root.rerun.restart();
            } else {
                root.forceRead = false;
            }
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "deviceBattery"

        function refresh(): void {
            root.refresh(true);
        }

        function status(): string {
            return JSON.stringify(root.devices);
        }
    }
}
