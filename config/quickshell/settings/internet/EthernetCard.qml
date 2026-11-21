import QtQuick
import QtQuick.Layouts
import "../../theme"

// Ethernet status card for the Internet page. The page supplies the nmcli
// state and owns the expanded flag; the card only renders it and reports the
// click on the summary row.
Rectangle {
    id: root

    property string state: "Unavailable"
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: root.state === "Connected"
                    ? Colors.primaryContainer : Colors.surfaceContainerHighest
                Text {
                    anchors.centerIn: parent
                    text: Icons.ethernet
                    color: root.state === "Connected"
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
                    text: root.state
                        + (root.connection ? " · " + root.connection : "")
                        + (root.device ? " (" + root.device + ")" : "")
                    color: root.state === "Connected" ? Colors.primary : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: root.state === "Connected"
                text: root.expanded ? Icons.chevronLeft : Icons.chevronRight
                rotation: root.expanded ? -90 : 90
                color: Colors.onSurfaceVariant
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.medium
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 4
            visible: root.state === "Connected" && root.expanded

            Text { text: "Device"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { Layout.fillWidth: true; text: root.device || "—"; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight }

            Text { visible: root.ip4 !== ""; text: "IPv4"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.ip4 !== ""; Layout.fillWidth: true; text: root.ip4; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight }

            Text { visible: root.gateway4 !== ""; text: "Gateway"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.gateway4 !== ""; Layout.fillWidth: true; text: root.gateway4; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight }

            Text { visible: root.dns !== ""; text: "DNS"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.dns !== ""; Layout.fillWidth: true; text: root.dns; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight; wrapMode: Text.Wrap }

            Text { visible: root.mac !== ""; text: "MAC"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.mac !== ""; Layout.fillWidth: true; text: root.mac; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight }

            Text { visible: root.speed !== ""; text: "Link"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.speed !== ""; Layout.fillWidth: true; text: root.speed; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight; wrapMode: Text.Wrap }

            Text { visible: root.ip6 !== ""; text: "IPv6"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
            Text { visible: root.ip6 !== ""; Layout.fillWidth: true; text: root.ip6; color: Colors.onSurface; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall; elide: Text.ElideRight; wrapMode: Text.Wrap }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.state === "Connected"
        cursorShape: root.state === "Connected" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggleExpanded()
    }
}
