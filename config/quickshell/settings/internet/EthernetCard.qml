import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../bar/components"

// Ethernet status card for the Internet page. The page supplies the nmcli
// state and owns the expanded flag; the card only renders it and reports the
// click on the summary row. Only the summary row toggles the card, so the
// detail values stay free for CopyableValue (click to copy).
Rectangle {
    id: root

    property string connectionState: "Unavailable"
    property string connection: ""
    property string device: ""
    property string mac: ""
    property string speed: ""
    property string ip4: ""
    property string gateway4: ""
    property string dns: ""
    property string ip6: ""
    property bool expanded: false

    signal toggleExpanded()

    Layout.fillWidth: true
    implicitHeight: ethCol.implicitHeight + 20
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    ColumnLayout {
        id: ethCol
        anchors { fill: parent; margins: 10 }
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: summaryRow.implicitHeight

            RowLayout {
                id: summaryRow
                anchors.fill: parent
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: root.connectionState === "Connected"
                        ? Colors.primaryContainer : Colors.surfaceContainerHighest
                    Text {
                        anchors.centerIn: parent
                        text: Icons.ethernet
                        color: root.connectionState === "Connected"
                            ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: "Ethernet"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.connectionState
                            + (root.connection ? " · " + root.connection : "")
                            + (root.device ? " (" + root.device + ")" : "")
                        color: root.connectionState === "Connected" ? Colors.primary : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: root.connectionState === "Connected"
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
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.connectionState === "Connected"
                cursorShape: root.connectionState === "Connected" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.toggleExpanded()
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 4
            visible: root.connectionState === "Connected" && root.expanded

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

            Text { visible: root.speed !== ""; text: "Link"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.speed !== ""; value: root.speed; wrap: true }

            Text { visible: root.ip6 !== ""; text: "IPv6"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            CopyableValue { visible: root.ip6 !== ""; value: root.ip6; wrap: true }
        }
    }
}
