import QtQuick
import "../../services"
import "../../theme"

// Headset battery status: flat headphones glyph, device name and percentage.
//
// The status only exists while a connected audio device actually reports a
// battery, so desktops and sessions without a headset keep the bar unchanged.
// A charging headset tints the glyph primary; 15% or less turns the percentage
// red, matching the laptop battery status.
//
// This is a status, not a menu: the click forces a fresh helper read, which the
// rotating refresh glyph in the trailing slot reports, and it never opens a
// sheet. The device name is capped and elided so the percentage stays readable.
//
// When the helper could not re-read the headset and fell back to an older
// sample, a small clock marks the value as cached: the percentage is still the
// last known level, not a live measurement.
StatusItem {
    id: root

    visible: DeviceBatteryService.available

    icon: Icons.headphones
    iconColor: DeviceBatteryService.low
        ? Colors.error
        : DeviceBatteryService.charging
            ? Colors.primary
            : Colors.onSurfaceVariant
    leadingText: DeviceBatteryService.available ? DeviceBatteryService.deviceName : ""
    leadingTextMaxWidth: 160
    leadingTextColor: Colors.onSurfaceVariant
    text: DeviceBatteryService.available
        ? DeviceBatteryService.percentage + "%"
        : ""
    textColor: DeviceBatteryService.low
        ? Colors.error
        : Colors.onSurfaceVariant
    textWeight: Typography.weight.bold
    trailingIcon: DeviceBatteryService.refreshing
        ? Icons.refresh
        : DeviceBatteryService.stale
            ? Icons.schedule
            : ""
    trailingIconColor: Colors.onSurfaceVariant
    spacing: 4

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: DeviceBatteryService.refresh(true)
    }

    RotationAnimation {
        target: root.trailingIconItem
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: DeviceBatteryService.refreshing

        onStopped: root.trailingIconItem.rotation = 0
    }
}
