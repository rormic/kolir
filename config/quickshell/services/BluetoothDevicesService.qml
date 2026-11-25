pragma Singleton
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import "."
import "bluetooth/Devices.js" as Devices

// Connected Bluetooth devices, as the bar capsule sees them.
//
// BlueZ's own device model is the source of truth; this singleton only mirrors
// the connected subset into one sorted array so the capsule can name the
// device it leads with and count the rest. A one-second snapshot is used
// because a binding on `Bluetooth.devices.values` does not re-evaluate when a
// device's `connected` flag flips (the same reason DeviceBatteryService keeps
// its own snapshot timer). The snapshot is only assigned when something
// actually changed, so the pill does not rebuild every second.
//
// Battery values come from DeviceBatteryService when its helper knows the
// device (exact Sony MDR readings, cached fallbacks) and otherwise from
// Quickshell's coarse `battery` property, so the capsule and the Bluetooth
// settings row always agree.
QtObject {
    id: root

    // [{ address, name, icon, battery }] where `battery` is
    // { percent, charging, stale, cached, exact } or null. Audio devices come
    // first, then input devices, then the rest.
    property var devices: []

    readonly property int count: root.devices.length
    readonly property bool available: root.count > 0
    readonly property var primary: root.available ? root.devices[0] : null
    readonly property string deviceName: root.primary ? root.primary.name : ""
    readonly property string deviceIcon: root.primary ? root.primary.icon : ""
    // Connected devices other than the one the pill names; shown as "+N".
    readonly property int others: Math.max(0, root.count - 1)

    readonly property var battery: root.primary ? root.primary.battery : null
    readonly property bool hasBattery: root.battery !== null
    readonly property int percentage: root.hasBattery ? root.battery.percent : 0
    readonly property bool charging: root.hasBattery && root.battery.charging === true
    readonly property bool stale: root.hasBattery && root.battery.stale === true
    readonly property bool low: root.hasBattery && !root.charging
        && root.percentage <= 15

    // Last emitted snapshot signature, so an identical poll is a no-op.
    property string signature: ""

    function exactBattery(address) {
        const readings = DeviceBatteryService.devices || [];
        for (let index = 0; index < readings.length; index++) {
            if (String(readings[index].address || "").toUpperCase() === address)
                return readings[index];
        }
        return null;
    }

    // Prefer the helper's exact value, fall back to BlueZ's coarse one. A
    // device that reports neither simply has no battery entry.
    function batteryOf(address, device) {
        const exact = root.exactBattery(address);
        if (exact !== null) {
            return {
                percent: exact.percent,
                charging: exact.charging === true,
                stale: exact.stale === true,
                cached: exact.cached === true,
                exact: true,
            };
        }

        if (device && device.batteryAvailable) {
            const percent = Math.round(Number(device.battery) * 100);
            if (isFinite(percent) && percent >= 0 && percent <= 100) {
                return {
                    percent: percent,
                    charging: false,
                    stale: false,
                    cached: false,
                    exact: false,
                };
            }
        }

        return null;
    }

    function snapshot() {
        const found = [];
        const list = Bluetooth.devices && Bluetooth.devices.values
            ? Bluetooth.devices.values
            : [];

        for (let index = 0; index < list.length; index++) {
            const device = list[index];
            if (!device || !device.connected)
                continue;

            const address = String(device.address || "").toUpperCase();
            found.push({
                address: address,
                name: String(device.name || device.deviceName || "Bluetooth device"),
                icon: String(device.icon || ""),
                battery: root.batteryOf(address, device),
            });
        }

        const sorted = Devices.sortDevices(found);
        const parts = [];
        for (let index = 0; index < sorted.length; index++) {
            const device = sorted[index];
            const battery = device.battery;
            parts.push([
                device.address,
                device.name,
                device.icon,
                battery ? battery.percent : "",
                battery && battery.charging ? "1" : "0",
                battery && battery.stale ? "1" : "0",
            ].join("|"));
        }

        return { devices: sorted, signature: parts.join("\n") };
    }

    function sync() {
        const state = root.snapshot();
        if (state.signature === root.signature)
            return;

        root.signature = state.signature;
        root.devices = state.devices;
    }

    // One snapshot a second: connecting or dropping a device shows up within
    // one tick, and a mostly idle desktop only iterates a handful of objects.
    property Timer poll: Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.sync()
    }

    // The battery helper has its own cadence; merge a fresh reading at once
    // instead of waiting for the next snapshot tick.
    property Connections batteryWatch: Connections {
        target: DeviceBatteryService

        function onDevicesChanged() {
            root.sync();
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "bluetoothDevices"

        function status(): string {
            return JSON.stringify(root.devices);
        }
    }
}
