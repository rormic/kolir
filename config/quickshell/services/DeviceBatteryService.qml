pragma Singleton
import QtQuick
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
// caches exact readings for a few minutes so it does not reconnect constantly.
QtObject {
    id: root

    // [{ address, name, percent, charging, source, exact }], best source first.
    property var devices: []

    property bool reading: false
    property bool pending: false
    property bool warned: false

    readonly property var primary: root.devices.length > 0 ? root.devices[0] : null
    readonly property bool available: root.primary !== null
    readonly property int percentage: root.primary ? root.primary.percent : 0
    readonly property bool charging: root.primary ? root.primary.charging : false
    readonly property bool low: root.available && !root.charging && root.percentage <= 15
    readonly property string deviceName: root.primary ? root.primary.name : ""

    function refresh() {
        if (root.reading) {
            root.pending = true;
            return;
        }

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

            clean.push({
                address: typeof entry.address === "string" ? entry.address : "",
                name: typeof entry.name === "string" && entry.name !== ""
                    ? entry.name
                    : "Bluetooth device",
                percent: percent,
                charging: entry.charging === true,
                source: typeof entry.source === "string" ? entry.source : "",
                exact: entry.exact === true,
            });
        }

        root.devices = clean;
    }

    // One poll a minute. The helper is fast (the exact value is cached), and a
    // connect/disconnect show up within one interval.
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

        onTriggered: root.refresh()
    }

    property Process reader: Process {
        command: [
            "python3",
            ShellPaths.deviceBatteryScript,
            "--state", ShellPaths.deviceBatteryState,
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }

        onExited: (exitCode, exitStatus) => {
            root.reading = false;
            if (root.pending) {
                root.pending = false;
                root.rerun.restart();
            }
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "deviceBattery"

        function refresh(): void {
            root.refresh();
        }

        function status(): string {
            return JSON.stringify(root.devices);
        }
    }
}
