pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../bar/components"
import "internet"

// Internet management page shown inside the settings popup. Uses nmcli
// (NetworkManager) for Wi-Fi control and to report Ethernet status.
Item {
    id: root

    signal back()

    property int topInset: 0

    implicitWidth: 380
    // Tall enough for the resting page (Ethernet + Wi-Fi + actions + network
    // list ≈ 424 px of body) so it does not start with a few pixels of scroll;
    // the expanded Ethernet details and the connection form still scroll.
    // Mirrored by `internetHeight` in SettingsMenu.qml.
    implicitHeight: 546

    NetworkController {
        id: net
        active: root.visible
        onResetRequested: root.resetForms()
    }

    function resetForms() {
        net.formMode = "";
        net.formNetwork = null;
        net.formSsid = "";
        net.formPassword = "";
        net.formShowPassword = false;
        net.formBusy = false;
        net.formError = "";
        net.formSecurityIndex = 1;
    }

    // ── Header ─────────────────────────────────────────────────────────────
    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Internet"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 10

            // Ethernet status
            EthernetCard {
                connectionState: net.ethernetState
                connection: net.ethernetConnection
                device: net.ethernetDevice
                mac: net.ethernetMac
                speed: net.ethernetSpeed
                ip4: net.ethernetIp4
                gateway4: net.ethernetGateway4
                dns: net.ethernetDns
                ip6: net.ethernetIp6
                expanded: net.ethernetDetailsExpanded
                onToggleExpanded: net.ethernetDetailsExpanded = !net.ethernetDetailsExpanded
            }

            // Wi-Fi adapter card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wifiCard.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: wifiCard
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: Dimensions.radius.small + 2
                            color: net.wifiEnabled ? Colors.primaryContainer : Colors.surfaceContainerHighest
                            Text {
                                anchors.centerIn: parent
                                text: net.wifiEnabled ? Icons.wifi : Icons.wifiOff
                                color: net.wifiEnabled ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
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
                                    if (!net.hasWifiDevice) return "No adapter found";
                                    if (!net.wifiEnabled) return "Disabled";
                                    if (net.activeWifi) return "Connected · " + net.activeWifi;
                                    return "Enabled";
                                }
                                color: net.wifiConnected ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: net.wifiEnabled
                            interactive: net.hasWifiDevice
                            onToggled: value => net.setWifiEnabled(value)
                        }
                    }

                    Text {
                        visible: net.lastError !== ""
                        Layout.fillWidth: true
                        text: net.lastError
                        color: Colors.error
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Actions row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: net.hasWifiDevice

                Rectangle {
                    id: scanBtn
                    property bool hovered: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.full
                    color: Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: scanBtn.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: net.wifiEnabled ? 1.0 : 0.5
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Colors.stateLayer(Colors.primary, 0.16)
                        opacity: scanBtn.hovered ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

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
                            RotationAnimation on rotation {
                                from: 0; to: 360; duration: 1000
                                loops: Animation.Infinite
                                running: net.scanning
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: net.scanning ? "Scanning…" : "Refresh"
                            color: scanBtn.hovered ? Colors.primary : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.medium
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: net.wifiEnabled
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: scanBtn.hovered = containsMouse
                        onClicked: net.refreshAll(true)
                    }
                }

                Rectangle {
                    id: hiddenBtn
                    property bool hovered: false
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.full
                    color: hiddenBtn.hovered ? Colors.stateLayer(Colors.primary, 0.16) : Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: hiddenBtn.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: net.wifiEnabled ? 1.0 : 0.5
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.add
                        color: hiddenBtn.hovered ? Colors.primary : Colors.onSurface
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: net.wifiEnabled
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: hiddenBtn.hovered = containsMouse
                        onClicked: {
                            net.formMode = net.formMode === "hidden" ? "" : "hidden";
                            net.formNetwork = null;
                            net.formSsid = "";
                            net.formPassword = "";
                            net.formShowPassword = false;
                            net.formError = "";
                            net.formSecurityIndex = 1;
                        }
                    }
                }
            }

            // Connection form (password or hidden network)
            WifiConnectionForm {
                mode: net.formMode
                visible: net.formMode === "hidden"
                    || (net.formMode === "password" && net.formNetwork !== null)
                ssid: net.formMode === "password"
                    ? (net.formNetwork ? net.formNetwork.ssid : "")
                    : net.formSsid
                showPassword: net.formShowPassword
                busy: net.formBusy
                error: net.formError
                securityIndex: net.formSecurityIndex
                onPasswordEdited: value => net.formPassword = value
                onSsidEdited: value => net.formSsid = value
                onShowPasswordToggled: net.formShowPassword = !net.formShowPassword
                onSecurityIndexSelected: index => net.formSecurityIndex = index
                onSubmitRequested: {
                    if (net.formMode === "password")
                        net.submitPasswordForm();
                    else if (net.formMode === "hidden")
                        net.submitHiddenForm();
                }
                onCancelRequested: root.resetForms()
            }

            // Networks header
            RowLayout {
                Layout.fillWidth: true
                visible: net.hasWifiDevice
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi networks"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }
                Text {
                    text: net.wifiNetworks.length + (net.wifiNetworks.length === 1 ? " network" : " networks")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
            }

            // Networks list
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                visible: net.hasWifiDevice
                radius: Dimensions.radius.medium
                color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
                clip: true

                ListView {
                    id: netList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: net.wifiNetworks

                    delegate: WifiNetworkRow {
                        required property var modelData

                        width: netList.width
                        network: modelData
                        savedMap: net.savedWifi
                        onConnectRequested: net.connectNetwork(modelData)
                        onForgetRequested: net.forgetNetwork(modelData)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: netList.count === 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: net.wifiEnabled ? Icons.wifi : Icons.wifiOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                        font.family: Typography.iconFont
                        font.pixelSize: 26
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !net.wifiEnabled ? "Wi-Fi is off" : "No networks found"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }
            }
        }
    }
}
