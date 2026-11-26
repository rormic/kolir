import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../bar/components"

// Wi-Fi status card for the Internet page. The page supplies the nmcli state
// and owns the expanded flag; the card renders the summary, the radio switch
// and the copyable details of the connected network. Only the summary area
// left of the switch toggles the card, so the switch keeps working and the
// detail values stay free for CopyableValue.
Rectangle {
    id: root

    property bool wifiEnabled: false
    property bool hasWifiDevice: false
    property bool connected: false
    property string connection: ""
    property string ssid: ""
    property string bssid: ""
    property string device: ""
    property string mac: ""
    property string ip4: ""
    property string gateway4: ""
    property string dns: ""
    property string ip6: ""
    property string security: ""
    property string channel: ""
    property string rate: ""
    property int signal: 0
    property string error: ""
    property bool expanded: false

    readonly property string securityLabel: root.security && root.security !== "--"
        ? root.security : "Open"

    signal toggleExpanded()
    signal enabledToggled(bool enabled)

    Layout.fillWidth: true
    implicitHeight: wifiCol.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    ColumnLayout {
        id: wifiCol
        anchors { fill: parent; margins: 12 }
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: summaryRow.implicitHeight

            RowLayout {
                id: summaryRow
                anchors.fill: parent
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.small + 2
                    color: root.wifiEnabled ? Colors.primaryContainer : Colors.surfaceContainerHighest
                    Text {
                        anchors.centerIn: parent
                        text: root.wifiEnabled ? Icons.wifi : Icons.wifiOff
                        color: root.wifiEnabled ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "Wi-Fi"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (!root.hasWifiDevice) return "No adapter found";
                            if (!root.wifiEnabled) return "Disabled";
                            if (root.connected) {
                                const name = root.ssid || root.connection;
                                return name ? "Connected · " + name : "Connected";
                            }
                            return "Enabled";
                        }
                        color: root.connected ? Colors.primary : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: root.connected
                    text: root.expanded ? Icons.chevronLeft : Icons.chevronRight
                    rotation: root.expanded ? -90 : 90
                    color: Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.medium
                    Behavior on rotation {
                        NumberAnimation {
                            duration: Motion.rotate
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.emphasizedCurve
                        }
                    }
                }

                Toggle {
                    id: wifiToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: root.wifiEnabled
                    interactive: root.hasWifiDevice
                    onToggled: checked => root.enabledToggled(checked)
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: wifiToggle.width + summaryRow.spacing
                hoverEnabled: true
                enabled: root.connected
                cursorShape: root.connected ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.toggleExpanded()
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 4
            visible: root.connected && root.expanded

            Text { visible: root.ssid !== ""; text: "SSID"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.ssid !== ""; value: root.ssid }

            // Only when the NetworkManager profile was renamed away from the SSID.
            Text { visible: root.connection !== "" && root.connection !== root.ssid; text: "Profile"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.connection !== "" && root.connection !== root.ssid; value: root.connection }

            Text { visible: root.bssid !== ""; text: "BSSID"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.bssid !== ""; value: root.bssid }

            Text { text: "Device"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { value: root.device }

            Text { visible: root.ip4 !== ""; text: "IPv4"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.ip4 !== ""; value: root.ip4 }

            Text { visible: root.gateway4 !== ""; text: "Gateway"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.gateway4 !== ""; value: root.gateway4 }

            Text { visible: root.dns !== ""; text: "DNS"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.dns !== ""; value: root.dns; wrap: true }

            Text { visible: root.mac !== ""; text: "MAC"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.mac !== ""; value: root.mac }

            Text { text: "Security"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { value: root.securityLabel }

            Text { visible: root.signal > 0; text: "Signal"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.signal > 0; value: root.signal + " %" }

            Text { visible: root.channel !== ""; text: "Channel"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.channel !== ""; value: root.channel }

            Text { visible: root.rate !== ""; text: "Link"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.rate !== ""; value: root.rate; wrap: true }

            Text { visible: root.ip6 !== ""; text: "IPv6"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.ip6 !== ""; value: root.ip6; wrap: true }
        }

        Text {
            visible: root.error !== ""
            Layout.fillWidth: true
            text: root.error
            color: Colors.error
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            wrapMode: Text.Wrap
        }
    }
}
