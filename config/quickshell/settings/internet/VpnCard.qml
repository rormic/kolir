pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../bar/components"
import "../../services"

// VPN card for the Internet page, below the Wi-Fi network list. VpnService
// owns the profiles, the active tunnel details and the busy/error state; the
// page owns the expanded flag. Only the summary area left of the switch
// toggles the card, so the switch keeps working and the detail values stay
// free for CopyableValue (click to copy).
Rectangle {
    id: root

    property bool expanded: false
    // Connected Wi-Fi profile and its state; a profile can be bound as its
    // secondary connection ("Connect on <Wi-Fi>").
    property string wifiProfile: ""
    property bool wifiConnected: false

    readonly property int profileCount: VpnService.profiles.length
    readonly property var wg: VpnService.wg || ({})
    readonly property var secondaries: VpnService.wifiSecondaries || []

    readonly property string subtitle: {
        if (!VpnService.probed)
            return "Checking…";
        if (!VpnService.available)
            return "NetworkManager unavailable";
        if (VpnService.busy)
            return "Working…";
        if (VpnService.connected)
            return VpnService.activeName !== ""
                ? "Connected · " + VpnService.activeName : "Connected";
        if (root.profileCount > 0)
            return root.profileCount + (root.profileCount === 1 ? " profile · off" : " profiles · off");
        return "No profiles";
    }

    signal toggleExpanded()

    Layout.fillWidth: true
    implicitHeight: vpnCol.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    Component.onCompleted: {
        if (root.wifiConnected && root.wifiProfile !== "")
            VpnService.refreshWifiSecondaries(root.wifiProfile);
    }
    onWifiProfileChanged: {
        if (root.wifiProfile !== "")
            VpnService.refreshWifiSecondaries(root.wifiProfile);
    }

    ColumnLayout {
        id: vpnCol
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
                    color: VpnService.connected
                        ? Colors.primaryContainer : Colors.surfaceContainerHighest
                    Text {
                        anchors.centerIn: parent
                        text: Icons.vpnLock
                        color: VpnService.connected ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "VPN"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.subtitle
                        color: VpnService.connected ? Colors.primary : Colors.onSurfaceVariant
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
                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                Toggle {
                    id: vpnToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: VpnService.connected
                    interactive: VpnService.available
                        && VpnService.profiles.length > 0
                        && !VpnService.busy
                    onToggled: VpnService.toggle(null)
                }
            }

            // Only the summary left of the switch toggles the card.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: vpnToggle.width + summaryRow.spacing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleExpanded()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.expanded

            // Profiles header with the import action
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "VPN profiles"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }
                Text {
                    text: root.profileCount + (root.profileCount === 1 ? " profile" : " profiles")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    id: importBtn
                    property bool hovered: false
                    Layout.preferredWidth: importRow.implicitWidth + 20
                    Layout.preferredHeight: 32
                    radius: Dimensions.radius.full
                    color: Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: importBtn.hovered && !VpnService.importing
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: VpnService.importing ? 0.6 : 1.0
                    Behavior on color { ColorAnimation { duration: Motion.hover } }

                    StateLayer {
                        shown: importBtn.hovered && !VpnService.importing
                        strength: 0.16
                    }

                    Row {
                        id: importRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.add
                            color: importBtn.hovered && !VpnService.importing
                                ? Colors.primary : Colors.onSurface
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: VpnService.importing ? "Importing…" : "Import"
                            color: importBtn.hovered && !VpnService.importing
                                ? Colors.primary : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.medium
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !VpnService.importing
                        cursorShape: VpnService.importing
                            ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onContainsMouseChanged: importBtn.hovered = containsMouse
                        onClicked: VpnService.importProfile()
                    }
                }

                Text {
                    id: importCancel
                    property bool hovered: false
                    visible: VpnService.importing
                    text: "Cancel"
                    color: importCancel.hovered ? Colors.primary : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: importCancel.hovered = containsMouse
                        onClicked: VpnService.cancelImport()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.profileCount === 0
                text: "No VPN profiles. Import a WireGuard .conf or OpenVPN .ovpn file."
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }

            // Profiles (a plain Column: the page's Flickable does the scrolling)
            Column {
                id: profileColumn

                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: VpnService.profiles

                    delegate: VpnProfileRow {
                        required property var modelData

                        width: profileColumn.width
                        profile: modelData
                        busy: VpnService.busy
                        wifiProfile: root.wifiProfile
                        wifiConnected: root.wifiConnected
                        wifiSecondary: root.secondaries.indexOf(modelData.uuid) >= 0
                        onConnectRequested: VpnService.activate(modelData)
                        onDisconnectRequested: VpnService.deactivate(modelData)
                        onAutoconnectToggled: enabled => VpnService.setAutoconnect(modelData, enabled)
                        onNeverDefaultToggled: enabled => VpnService.setNeverDefault(modelData, enabled)
                        onWifiSecondaryToggled: enabled => VpnService.setWifiSecondary(root.wifiProfile, modelData, enabled)
                    }
                }
            }

            // Active tunnel details
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 4
                visible: VpnService.connected

                Text { visible: VpnService.activeDevice !== ""; text: "Device"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: VpnService.activeDevice !== ""; value: VpnService.activeDevice }

                Text { visible: VpnService.ip4 !== ""; text: "IPv4"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: VpnService.ip4 !== ""; value: VpnService.ip4 }

                Text { visible: VpnService.gateway4 !== ""; text: "Gateway"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: VpnService.gateway4 !== ""; value: VpnService.gateway4 }

                Text { visible: VpnService.dns !== ""; text: "DNS"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: VpnService.dns !== ""; value: VpnService.dns; wrap: true }

                Text { visible: VpnService.ip6 !== ""; text: "IPv6"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: VpnService.ip6 !== ""; value: VpnService.ip6; wrap: true }

                Text { visible: (root.wg.endpoint || "") !== ""; text: "Endpoint"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: (root.wg.endpoint || "") !== ""; value: root.wg.endpoint || ""; wrap: true }

                Text { visible: (root.wg.handshake || "") !== ""; text: "Handshake"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: (root.wg.handshake || "") !== ""; value: root.wg.handshake || "" }

                Text { visible: (root.wg.rx || "") !== ""; text: "Transfer"; color: Colors.onSurfaceVariant; font.family: Typography.barFont; font.pixelSize: Typography.size.labelSmall }
                CopyableValue { visible: (root.wg.rx || "") !== ""; value: (root.wg.rx || "") + " ↓ · " + (root.wg.tx || "") + " ↑" }
            }

            Text {
                Layout.fillWidth: true
                visible: VpnService.importError !== ""
                text: VpnService.importError
                color: Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: VpnService.lastError !== ""
                text: VpnService.lastError
                color: Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }

            TailscaleSection {
                Layout.fillWidth: true
                visible: TailscaleService.installed
            }
        }
    }
}
