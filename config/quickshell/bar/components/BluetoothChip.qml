import QtQuick
import "../../services"
import "../../services/bluetooth/Devices.js" as Devices
import "../../theme"

// Connected Bluetooth devices capsule.
//
// A control, not a status: it shows the device the user is most likely to care
// about (an audio device first, then input devices), how many more are
// connected and the headset charge when BlueZ or the exact-battery helper
// reports one. A left click opens Settings → Bluetooth, so the capsule is the
// bar's shortcut to pairing, forgetting or inspecting devices.
//
// The capsule only exists while something is connected; a machine without an
// adapter or without paired devices keeps the bar unchanged. The device name
// elides before the percentage, and the low-charge/charging colors match the
// Bluetooth settings row.
Pill {
    id: root

    signal activated()

    // Bound by Bar to the settings sheet's Bluetooth page.
    property bool popupActive: false

    visible: BluetoothDevicesService.available

    icon: Devices.glyph(Icons, BluetoothDevicesService.deviceIcon)
    iconColor: BluetoothDevicesService.low
        ? Colors.error
        : BluetoothDevicesService.charging
            ? Colors.primary
            : Colors.onSurfaceVariant
    text: BluetoothDevicesService.deviceName
        + (BluetoothDevicesService.others > 0
            ? " +" + BluetoothDevicesService.others
            : "")
    textMaxWidth: 150
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    trailingText: BluetoothDevicesService.hasBattery
        ? BluetoothDevicesService.percentage + "%"
        : ""
    trailingTextColor: BluetoothDevicesService.low
        ? Colors.error
        : BluetoothDevicesService.charging
            ? Colors.primary
            : Colors.onSurfaceVariant
    // A cached sample is the last known level, not a live measurement.
    trailingIcon: BluetoothDevicesService.stale ? Icons.schedule : ""
    trailingIconColor: Colors.onSurfaceVariant
    spacing: 5
    active: root.popupActive

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
