import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../theme"
import "../bar/components"

// Bluetooth management page, shown inside the settings popup. Navigation is
// handled by SettingsMenu; this page only reports back/close and device
// actions back to the BlueZ model.
Item {
    id: root

    signal back()
    signal close()

    property int topInset: 0

    implicitWidth: 380
    implicitHeight: 520

    property var adapter: Bluetooth.defaultAdapter

    readonly property bool scanning: !!root.adapter && root.adapter.discovering

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

    // ── Header ─────────────────────────────────────────────────────────────
    Item {
        id: header

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.topInset
        }
        height: 46

        Rectangle {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: 1
            color: Colors.withAlpha(Colors.outlineVariant, 0.25)
        }

        IconButton {
            id: backButton

            anchors {
                left: parent.left
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            icon: Icons.arrowBack
            iconSize: Dimensions.icon.medium
            onClicked: root.back()
        }

        Text {
            anchors {
                left: backButton.right
                leftMargin: 2
                verticalCenter: parent.verticalCenter
            }
            text: "Bluetooth"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleLarge
            font.weight: Typography.weight.bold
        }
    }

    // ── No adapter ─────────────────────────────────────────────────────────
    Item {
        id: emptyAdapter

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: !root.adapter

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Icons.bluetoothDisabled
                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                font.family: Typography.iconFont
                font.pixelSize: 32
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No Bluetooth adapter"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.bodyMedium
                font.weight: Typography.weight.medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bluetooth hardware was not found"
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
            }
        }
    }

    // ── Adapter present ────────────────────────────────────────────────────
    ColumnLayout {
        id: body

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 14
        }
        spacing: 10
        visible: !!root.adapter

        // Adapter card
        Rectangle {
            id: adapterCard

            Layout.fillWidth: true
            implicitHeight: adapterContent.implicitHeight + 24
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

            readonly property bool blocked: !!root.adapter
                && root.adapter.state === BluetoothAdapterState.Blocked

            ColumnLayout {
                id: adapterContent

                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: Dimensions.radius.small + 2
                        color: root.adapter && root.adapter.enabled
                            ? Colors.primaryContainer
                            : Colors.surfaceContainerHighest

                        Text {
                            anchors.centerIn: parent
                            text: Icons.bluetooth
                            color: root.adapter && root.adapter.enabled
                                ? Colors.onPrimaryContainer
                                : Colors.onSurfaceVariant
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.large
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: root.adapter
                                ? (root.adapter.name || "Bluetooth adapter")
                                : ""
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.bodyMedium
                            font.weight: Typography.weight.medium
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (!root.adapter)
                                    return "";
                                if (!root.adapter.enabled)
                                    return "Disabled";
                                return BluetoothAdapterState.toString(root.adapter.state);
                            }
                            color: root.blocked ? Colors.error : Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignVCenter
                        checked: root.adapter ? root.adapter.enabled : false
                        onToggled: value => {
                            if (root.adapter)
                                root.adapter.enabled = value;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: "Visible to other devices"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignVCenter
                        checked: root.adapter ? root.adapter.discoverable : false
                        interactive: root.adapter && root.adapter.enabled
                        onToggled: value => {
                            if (root.adapter)
                                root.adapter.discoverable = value;
                        }
                    }
                }
            }
        }

        // Pair a new device
        Rectangle {
            id: addDevice

            property bool hovered: false

            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Dimensions.radius.full
            color: addDevice.hovered
                ? Colors.stateLayer(Colors.primary, 0.16)
                : Colors.surfaceContainerHigh
            border.width: 1
            border.color: addDevice.hovered
                ? Colors.withAlpha(Colors.primary, 0.6)
                : Colors.withAlpha(Colors.outlineVariant, 0.22)

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    id: scanIcon

                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.refresh
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.medium

                    RotationAnimation {
                        target: scanIcon
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.scanning
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.scanning ? "Scanning for devices…" : "Add device"
                    color: addDevice.hovered ? Colors.primary : Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.medium

                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: addDevice.hovered = containsMouse
                onClicked: {
                    if (!root.adapter)
                        return;

                    root.adapter.pairable = true;
                    root.adapter.discoverable = true;
                    root.adapter.discoverableTimeout = 120;
                }
            }
        }

        // Devices header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Devices"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.bold
            }

            Text {
                text: list.count + (list.count === 1 ? " device" : " devices")
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
            }
        }

        // Devices list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Dimensions.radius.medium
            color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
            clip: true

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: 4
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.adapter ? root.adapter.devices : []

                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                remove: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 140
                        easing.type: Easing.InCubic
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData

                    width: list.width
                    height: 54

                    readonly property bool hovered: rowHover.hovered
                    readonly property bool connected: modelData.connected

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
                            text: root.deviceGlyph(modelData.icon)
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
                            text: modelData.name
                                || modelData.deviceName
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
                            text: root.deviceStatus(modelData)
                                + (modelData.paired && !row.connected ? " · Paired" : "")
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
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.connected)
                                modelData.disconnect();
                            else
                                modelData.connect();
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
                        visible: !row.hovered && modelData.batteryAvailable

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.battery < 0.2
                                ? Icons.batteryLow
                                : Icons.batteryFull
                            color: Colors.onSurfaceVariant
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.small + 2
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(modelData.battery * 100) + "%"
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
                        visible: row.hovered && !modelData.pairing
                        onClicked: modelData.forget()
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: list.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Icons.bluetooth
                    color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                    font.family: Typography.iconFont
                    font.pixelSize: 26
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No devices yet"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                }
            }
        }
    }
}
