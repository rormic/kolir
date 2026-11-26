import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../bar/components"

// One VPN profile row inside VpnCard: type glyph, name, connection state and
// the row's own connect switch. The name/state column doubles as the handle
// for the inline options (auto-connect, split tunnel, connect-on-Wi-Fi), so
// the switch and the options' own toggles stay clickable. VpnService owns the
// profile data and every action; the row only reports taps.
Rectangle {
    id: root

    property var profile: null
    property bool busy: false
    property string wifiProfile: ""
    property bool wifiConnected: false
    property bool wifiSecondary: false
    // Inline options block, owned by the row itself.
    property bool expanded: false

    readonly property bool active: !!root.profile && !!root.profile.active
    readonly property string activeDevice: root.profile && root.profile.device
        ? root.profile.device : ""
    readonly property bool hasWifiOption: root.wifiConnected && root.wifiProfile !== ""

    readonly property string stateLabel: {
        if (!root.profile)
            return "Disconnected";

        let label;
        if (root.active)
            label = root.activeDevice !== ""
                ? "Connected · " + root.activeDevice : "Connected";
        else
            label = "Disconnected";

        if (root.profile.autoconnect)
            label += " · auto";
        if (root.profile.neverDefault)
            label += " · split";
        return label;
    }

    signal connectRequested()
    signal disconnectRequested()
    signal autoconnectToggled(bool enabled)
    signal neverDefaultToggled(bool enabled)
    signal wifiSecondaryToggled(bool enabled)

    function typeGlyph(type) {
        if (type === "wireguard")
            return Icons.shield;
        if (type === "tun")
            return Icons.ethernet;
        return Icons.vpnLock;
    }

    implicitHeight: rowCol.implicitHeight + 14
    radius: Dimensions.radius.small + 2
    color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)

    ColumnLayout {
        id: rowCol
        anchors { fill: parent; margins: 7 }
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
                    color: root.active
                        ? Colors.primaryContainer : Colors.surfaceContainerHighest
                    Text {
                        anchors.centerIn: parent
                        text: root.typeGlyph(root.profile ? root.profile.type : "")
                        color: root.active ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: root.profile ? root.profile.name : ""
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.medium
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.stateLabel
                        color: root.active ? Colors.primary : Colors.onSurfaceVariant
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
                    id: rowToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: root.active
                    interactive: !root.busy
                    onToggled: checked => checked
                        ? root.connectRequested() : root.disconnectRequested()
                }
            }

            // Only the left part opens the options; the switch keeps its tap.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: rowToggle.width + summaryRow.spacing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: root.expanded

            RowLayout {
                id: autoRow

                Layout.fillWidth: true
                spacing: 8

                Toggle {
                    id: autoToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: !!root.profile && !!root.profile.autoconnect
                    interactive: !root.busy
                    onToggled: checked => root.autoconnectToggled(checked)
                }
                Text {
                    Layout.fillWidth: true
                    text: "Auto-connect"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.autoconnectToggled(!autoToggle.checked)
                    }
                }
            }

            RowLayout {
                id: splitRow

                Layout.fillWidth: true
                spacing: 8

                Toggle {
                    id: splitToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: !!root.profile && !!root.profile.neverDefault
                    interactive: !root.busy
                    onToggled: checked => root.neverDefaultToggled(checked)
                }
                Text {
                    Layout.fillWidth: true
                    text: "Split tunnel"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.neverDefaultToggled(!splitToggle.checked)
                    }
                }
            }

            RowLayout {
                id: wifiRow

                Layout.fillWidth: true
                spacing: 8
                visible: root.hasWifiOption

                Toggle {
                    id: wifiToggle

                    Layout.alignment: Qt.AlignVCenter
                    checked: root.wifiSecondary
                    interactive: !root.busy
                    onToggled: checked => root.wifiSecondaryToggled(checked)
                }
                Text {
                    Layout.fillWidth: true
                    text: root.hasWifiOption ? "Connect on " + root.wifiProfile : ""
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.wifiSecondaryToggled(!wifiToggle.checked)
                    }
                }
            }
        }
    }
}
