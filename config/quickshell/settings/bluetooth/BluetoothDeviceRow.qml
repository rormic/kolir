import QtQuick
import Quickshell.Bluetooth
import "../../theme"
import "../../bar/components"

// One device row in the Bluetooth page: state accent, glyph, name, status,
// battery indicator and the hover-only forget action.
Item {
    id: row

    property var device: null

    readonly property bool hovered: rowHover.hovered
    readonly property bool connected: !!row.device && row.device.connected

    function deviceGlyph(icon) {
        switch (icon) {
            case "audio-headset":
            case "audio-headphones":
            case "headset":
                return Icons.headphones;
            case "audio-input-microphone":
            case "microphone":
                return Icons.mic;
            case "input-keyboard":
            case "keyboard":
                return Icons.keyboard;
            case "input-mouse":
            case "mouse":
                return Icons.mouse;
            case "phone":
            case "phone-android":
            case "smartphone":
                return Icons.smartphone;
            case "computer":
            case "laptop":
            case "laptop-mac":
                return Icons.laptop;
            case "wearable":
            case "watch":
                return Icons.watch;
            default:
                return Icons.devices;
        }
    }

    function deviceStatus(device) {
        if (device.pairing)
            return "Pairing…";

        switch (device.state) {
            case BluetoothDeviceState.Connected:
                return "Connected";
            case BluetoothDeviceState.Connecting:
                return "Connecting…";
            case BluetoothDeviceState.Disconnecting:
                return "Disconnecting…";
            default:
                return "Disconnected";
        }
    }

    height: 54

    HoverHandler {
        id: rowHover
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Dimensions.radius.medium
        color: row.hovered
            ? Colors.stateLayer(Colors.onSurface, 0.06)
            : "transparent"
        border.width: row.connected ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.35)

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // Connected accent bar
    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width: 2
        height: 18
        radius: 1
        visible: row.connected
        color: Colors.primary
    }

    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }
        width: 34
        height: 34
        radius: 10
        color: row.connected
            ? Colors.primaryContainer
            : Colors.surfaceContainerHigh

        Text {
            anchors.centerIn: parent
            text: row.deviceGlyph(row.device.icon)
            color: row.connected
                ? Colors.onPrimaryContainer
                : Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.medium
        }
    }

    Column {
        anchors {
            left: parent.left
            leftMargin: 54
            right: parent.right
            rightMargin: 56
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
            width: parent.width
            text: row.device.name
                || row.device.deviceName
                || "Unknown device"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            font.weight: row.connected
                ? Typography.weight.bold
                : Typography.weight.medium
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: row.deviceStatus(row.device)
                + (row.device.paired && !row.connected ? " · Paired" : "")
            color: row.connected ? Colors.primary : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            elide: Text.ElideRight
        }
    }

    // Row click area, kept below the trailing actions
    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (row.connected)
                row.device.disconnect();
            else
                row.device.connect();
        }
    }

    // Battery, replaced by "forget" on hover
    Row {
        id: batteryRow

        anchors {
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        spacing: 3
        visible: !row.hovered && row.device.batteryAvailable

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.device.battery < 0.2
                ? Icons.batteryLow
                : Icons.batteryFull
            color: Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.small + 2
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(row.device.battery * 100) + "%"
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
        }
    }

    IconButton {
        id: deleteButton

        anchors {
            right: parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        icon: Icons.trash
        iconSize: Dimensions.icon.medium
        visible: row.hovered && !row.device.pairing
        onClicked: row.device.forget()
    }
}
