import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../theme"
import "../services"
import "../bar/components"
import "bluetooth"

// Bluetooth management page, shown inside the settings popup. Navigation is
// handled by SettingsMenu; this page only reports back and device actions
// back to the BlueZ model.
Item {
    id: root

    signal back()

    property int topInset: 0

    implicitWidth: 380
    implicitHeight: 520

    property var adapter: Bluetooth.defaultAdapter

    readonly property bool scanning: !!root.adapter && root.adapter.discovering

    // Opening the page asks the device-battery helper for a fresh reading, so
    // an exact protocol value replaces BlueZ's coarse one without waiting for
    // the next 60 s poll. This one is forced: a detail page should show the
    // live level when the headset answers, not the four-minute cache.
    // Leaving the page stops a discovery it started, so no scan keeps running
    // behind the settings sheet.
    onVisibleChanged: {
        if (root.visible) {
            DeviceBatteryService.refresh(true);
        } else if (root.adapter) {
            root.adapter.discovering = false;
        }
    }

    // A discovery left running forever keeps the radio busy and drains the
    // battery, so it is bounded like the adapter's discoverable timeout.
    Timer {
        interval: 60000
        running: root.scanning
        onTriggered: if (root.adapter) root.adapter.discovering = false
    }

    // ── Header ─────────────────────────────────────────────────────────────
    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Bluetooth"
        onBack: root.back()
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

            readonly property bool canScan: !!root.adapter && root.adapter.enabled

            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Dimensions.radius.full
            color: Colors.surfaceContainerHigh
            opacity: addDevice.canScan ? 1 : 0.45
            border.width: 1
            border.color: addDevice.hovered && addDevice.canScan
                ? Colors.withAlpha(Colors.primary, 0.6)
                : Colors.withAlpha(Colors.outlineVariant, 0.22)

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            StateLayer {
                shown: addDevice.hovered && addDevice.canScan
                strength: 0.16
            }

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    id: scanIcon

                    anchors.verticalCenter: parent.verticalCenter
                    text: root.scanning ? Icons.refresh : Icons.add
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

                        onRunningChanged: if (!running) scanIcon.rotation = 0
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.scanning ? "Stop scanning" : "Add device"
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
                cursorShape: addDevice.canScan ? Qt.PointingHandCursor : Qt.ArrowCursor
                onContainsMouseChanged: addDevice.hovered = containsMouse
                onClicked: {
                    if (!addDevice.canScan)
                        return;

                    if (root.scanning) {
                        root.adapter.discovering = false;
                        return;
                    }

                    root.adapter.pairable = true;
                    root.adapter.discovering = true;
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

                delegate: BluetoothDeviceRow {
                    required property var modelData

                    width: list.width
                    device: modelData
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
