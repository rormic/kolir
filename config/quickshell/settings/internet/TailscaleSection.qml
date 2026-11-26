pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../bar/components"
import "../../services"

// Tailscale sub-card inside the VPN card. TailscaleService owns the daemon,
// the login state, the peer count and the exit-node list; this card renders
// them, forwards up/down and the exit-node choice, and keeps its own expanded
// flag because the exit-node picker and the addresses are secondary details.
Rectangle {
    id: root

    property bool expanded: false

    readonly property bool connected: TailscaleService.connected
    readonly property var exitNodes: TailscaleService.exitNodes || []
    readonly property var ips: TailscaleService.ips || []

    // The exit-node list with the "None" entry first, so one column renders
    // the whole radio group.
    readonly property var exitChoices: {
        const none = { id: "", name: "", dnsName: "", online: false, none: true };
        return [none].concat(root.exitNodes);
    }

    readonly property string subtitle: {
        if (!TailscaleService.daemonRunning)
            return "Daemon not running";
        if (TailscaleService.backendState === "NeedsLogin")
            return "Sign in required";
        if (TailscaleService.busy)
            return "Working…";
        if (TailscaleService.connected) {
            let label = TailscaleService.hostName !== ""
                ? "Connected · " + TailscaleService.hostName : "Connected";
            return label + " · " + TailscaleService.peersOnline + "/"
                + TailscaleService.peersTotal + " peers";
        }
        return "Disconnected";
    }

    function isExitNode(entry) {
        if (!entry || entry.none)
            return (TailscaleService.exitNode || "") === "";
        // The node id is exact; the names are what the daemon echoes back.
        return (TailscaleService.exitNodeId !== "" && TailscaleService.exitNodeId === entry.id)
            || TailscaleService.exitNode === entry.name
            || TailscaleService.exitNode === entry.dnsName;
    }

    implicitHeight: tailscaleCol.implicitHeight + 20
    radius: Dimensions.radius.small + 2
    color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)

    ColumnLayout {
        id: tailscaleCol
        anchors { fill: parent; margins: 10 }
        spacing: 6

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: summaryRow.implicitHeight

            RowLayout {
                id: summaryRow
                anchors.fill: parent
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Dimensions.radius.small
                    color: root.connected
                        ? Colors.primaryContainer : Colors.surfaceContainerHighest
                    Text {
                        anchors.centerIn: parent
                        text: Icons.hub
                        color: root.connected ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "Tailscale"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.subtitle
                        color: root.connected ? Colors.primary : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }
                }

                Text {
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
                    id: tailscaleToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: root.connected
                    interactive: TailscaleService.daemonRunning
                        && TailscaleService.backendState !== "NeedsLogin"
                        && !TailscaleService.busy
                    onToggled: checked => checked
                        ? TailscaleService.up() : TailscaleService.down()
                }
            }

            // Only the left part opens the details; the switch keeps its tap.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: tailscaleToggle.width + summaryRow.spacing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.expanded

            Text { Layout.fillWidth: true; text: "Exit node"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }

            Column {
                id: exitColumn

                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: root.exitChoices

                    delegate: Rectangle {
                        id: exitRow

                        required property var modelData

                        readonly property bool none: !!modelData.none
                        readonly property bool selected: root.isExitNode(modelData)
                        property bool hovered: false

                        width: exitColumn.width
                        height: 24
                        radius: Dimensions.radius.small
                        color: "transparent"

                        StateLayer {
                            shown: exitRow.hovered
                            strength: 0.10
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                            spacing: 6

                            Text {
                                text: exitRow.selected ? Icons.radioChecked : Icons.radioUnchecked
                                color: exitRow.selected ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.medium
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Motion.color
                                        easing.type: Easing.Bezier
                                        easing.bezierCurve: Motion.standardDecelerateCurve
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: exitRow.none ? "None" : (exitRow.modelData.name || exitRow.modelData.dnsName)
                                color: exitRow.selected ? Colors.onSurface : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.preferredWidth: 6
                                Layout.preferredHeight: 6
                                Layout.alignment: Qt.AlignVCenter
                                radius: 3
                                visible: !exitRow.none && !!exitRow.modelData.online
                                color: Colors.primary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: exitRow.hovered = containsMouse
                            onClicked: TailscaleService.setExitNode(exitRow.none
                                ? "" : (exitRow.modelData.name || exitRow.modelData.dnsName || ""))
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 4
                visible: TailscaleService.dnsName !== ""

                Text { text: "MagicDNS"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { Layout.fillWidth: true; value: TailscaleService.dnsName; wrap: true }
            }

            Column {
                id: ipsColumn

                Layout.fillWidth: true
                spacing: 2
                visible: root.ips.length > 0

                Text { text: "IP addresses"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }

                Repeater {
                    model: root.ips

                    delegate: CopyableValue {
                        required property var modelData

                        width: ipsColumn.width
                        value: modelData
                    }
                }
            }

            Repeater {
                model: TailscaleService.health || []

                delegate: Text {
                    required property var modelData

                    Layout.fillWidth: true
                    text: modelData
                    color: Colors.error
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    wrapMode: Text.Wrap
                }
            }

            Text {
                Layout.fillWidth: true
                visible: TailscaleService.hint !== ""
                text: TailscaleService.hint
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: TailscaleService.lastError !== ""
                text: TailscaleService.lastError
                color: Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }
        }
    }
}
