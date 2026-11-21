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
    implicitHeight: 520

    NetworkController {
        id: net
        active: root.visible
        onResetRequested: root.resetForms()
    }

    // ── State (owned by the nmcli controller) ─────────────────────────────
    property alias wifiEnabled: net.wifiEnabled
    property alias hasWifiDevice: net.hasWifiDevice
    property alias wifiDevice: net.wifiDevice
    property alias activeWifi: net.activeWifi
    property alias ethernetState: net.ethernetState
    property alias ethernetConnection: net.ethernetConnection
    property alias ethernetDevice: net.ethernetDevice
    property alias ethernetMac: net.ethernetMac
    property alias ethernetSpeed: net.ethernetSpeed
    property alias ethernetIp4: net.ethernetIp4
    property alias ethernetGateway4: net.ethernetGateway4
    property alias ethernetDns: net.ethernetDns
    property alias ethernetIp6: net.ethernetIp6
    property alias ethernetDetailsExpanded: net.ethernetDetailsExpanded
    property alias scanning: net.scanning
    property alias busy: net.busy
    property alias lastError: net.lastError

    property alias wifiNetworks: net.wifiNetworks
    property alias savedWifi: net.savedWifi

    // Password / hidden forms
    property alias formMode: net.formMode // "", "password", "hidden"
    property alias formNetwork: net.formNetwork
    property alias formSsid: net.formSsid
    property alias formPassword: net.formPassword
    property alias formShowPassword: net.formShowPassword
    property alias formBusy: net.formBusy
    property alias formError: net.formError
    property alias formSecurityIndex: net.formSecurityIndex

    property alias wifiConnected: net.wifiConnected

    function resetForms() {
        formMode = "";
        formNetwork = null;
        formSsid = "";
        formPassword = "";
        formShowPassword = false;
        formBusy = false;
        formError = "";
        formSecurityIndex = 1;
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
                connectionState: root.ethernetState
                connection: root.ethernetConnection
                device: root.ethernetDevice
                mac: root.ethernetMac
                speed: root.ethernetSpeed
                ip4: root.ethernetIp4
                gateway4: root.ethernetGateway4
                dns: root.ethernetDns
                ip6: root.ethernetIp6
                expanded: root.ethernetDetailsExpanded
                onToggleExpanded: root.ethernetDetailsExpanded = !root.ethernetDetailsExpanded
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
                                    if (root.activeWifi) return "Connected · " + root.activeWifi;
                                    return "Enabled";
                                }
                                color: root.wifiConnected ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: root.wifiEnabled
                            interactive: root.hasWifiDevice
                            onToggled: value => net.setWifiEnabled(value)
                        }
                    }

                    Text {
                        visible: root.lastError !== ""
                        Layout.fillWidth: true
                        text: root.lastError
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
                visible: root.hasWifiDevice

                Rectangle {
                    id: scanBtn
                    property bool hovered: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.full
                    color: scanBtn.hovered ? Colors.stateLayer(Colors.primary, 0.16) : Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: scanBtn.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: root.wifiEnabled ? 1.0 : 0.5
                    Behavior on color { ColorAnimation { duration: 150 } }

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
                                running: root.scanning
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.scanning ? "Scanning…" : "Refresh"
                            color: scanBtn.hovered ? Colors.primary : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.medium
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.wifiEnabled
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
                    opacity: root.wifiEnabled ? 1.0 : 0.5
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
                        enabled: root.wifiEnabled
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: hiddenBtn.hovered = containsMouse
                        onClicked: {
                            root.formMode = root.formMode === "hidden" ? "" : "hidden";
                            root.formNetwork = null;
                            root.formSsid = "";
                            root.formPassword = "";
                            root.formShowPassword = false;
                            root.formError = "";
                            root.formSecurityIndex = 1;
                        }
                    }
                }
            }

            // Connection form (password or hidden network)
            WifiConnectionForm {
                mode: root.formMode
                visible: root.formMode === "hidden"
                    || (root.formMode === "password" && root.formNetwork !== null)
                ssid: root.formMode === "password"
                    ? (root.formNetwork ? root.formNetwork.ssid : "")
                    : root.formSsid
                showPassword: root.formShowPassword
                busy: root.formBusy
                error: root.formError
                securityIndex: root.formSecurityIndex
                onPasswordEdited: value => root.formPassword = value
                onSsidEdited: value => root.formSsid = value
                onShowPasswordToggled: root.formShowPassword = !root.formShowPassword
                onSecurityIndexSelected: index => root.formSecurityIndex = index
                onSubmitRequested: {
                    if (root.formMode === "password")
                        net.submitPasswordForm();
                    else if (root.formMode === "hidden")
                        net.submitHiddenForm();
                }
                onCancelRequested: root.resetForms()
            }

            // Networks header
            RowLayout {
                Layout.fillWidth: true
                visible: root.hasWifiDevice
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi networks"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }
                Text {
                    text: root.wifiNetworks.length + (root.wifiNetworks.length === 1 ? " network" : " networks")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
            }

            // Networks list
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                visible: root.hasWifiDevice
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
                    model: root.wifiNetworks

                    delegate: WifiNetworkRow {
                        required property var modelData

                        width: netList.width
                        network: modelData
                        savedMap: root.savedWifi
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
                        text: root.wifiEnabled ? Icons.wifi : Icons.wifiOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                        font.family: Typography.iconFont
                        font.pixelSize: 26
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !root.wifiEnabled ? "Wi-Fi is off" : "No networks found"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }
            }
        }
    }
}
