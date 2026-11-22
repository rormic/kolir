pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Battery state for the bar indicator.
//
// UPower's DisplayDevice aggregates every internal battery, so machines with
// two packs still get one percentage and one charge state. The indicator is
// hidden on desktops: `expected` is only true for a portable chassis or when
// UPower actually reports a battery. A laptop whose battery is missing from
// UPower (removed, dead, or the daemon not running) therefore keeps the chip
// and Battery.qml draws the alert glyph instead of a charge level.
QtObject {
    id: root

    // SMBIOS chassis types (DMI specification) that ship with an internal
    // battery: portable, laptop, notebook, hand held, sub notebook, tablet,
    // convertible, detachable. 0 means the kernel reported no chassis type.
    readonly property var portableChassisTypes: [8, 9, 10, 11, 14, 30, 31, 32]

    // Read once at startup from /sys/class/dmi/id/chassis_type.
    property int chassisType: 0

    readonly property var display: UPower.displayDevice
    readonly property bool hasDisplay: !!root.display

    readonly property bool chassisPortable: root.portableChassisTypes.indexOf(root.chassisType) !== -1

    // True once UPower has answered. Before that, `isPresent` is still false
    // for a real battery, so the service must not conclude it is missing.
    readonly property bool upowerReady: root.hasDisplay && root.display.ready

    // Set after a short startup window so a laptop with no UPower daemon still
    // reports the missing battery instead of hiding the chip forever.
    property bool startupSettled: false

    // A usable internal battery: UPower reports the aggregate battery device
    // as physically present.
    readonly property bool present: root.upowerReady
        && root.display.isPresent
        && root.display.type === UPowerDeviceType.Battery

    // A laptop with no usable battery still needs the chip, so the missing
    // battery is visible instead of silently hiding the indicator. Waiting for
    // `upowerReady` or the startup window avoids a "missing" flash on every
    // shell start.
    readonly property bool expected: root.present
        || (root.chassisPortable && (root.upowerReady || root.startupSettled))

    readonly property int percentage: root.present
        ? Math.max(0, Math.min(100, Math.round(root.display.percentage)))
        : 0

    readonly property bool charging: root.present
        && (root.display.state === UPowerDeviceState.Charging
            || root.display.state === UPowerDeviceState.PendingCharge)

    // Low enough that the bar should warn: red icon/text while unplugged.
    readonly property bool low: root.present && !root.charging && root.percentage <= 15

    property Timer settleTimer: Timer {
        interval: 6000
        running: !root.upowerReady
        onTriggered: root.startupSettled = true
    }

    property FileView chassisReader: FileView {
        path: ShellPaths.chassisType
        printErrors: false

        onLoaded: {
            const value = parseInt(text().trim(), 10);
            root.chassisType = isNaN(value) ? 0 : value;
        }
        onLoadFailed: root.chassisType = 0
    }
}
