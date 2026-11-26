import QtQuick
import "../../theme"
import "../../bar/components"

// One Wi-Fi network row: connection accent, signal glyph, name, security
// label, signal percentage and the hover-only forget action. The page owns
// the nmcli actions.
Item {
    id: row

    property var network: null
    property var savedMap: ({})

    readonly property bool hovered: rowHover.hovered
    readonly property bool connected: !!row.network && !!row.network.connected
    readonly property bool saved: !!row.network
        && (!!row.network.saved || !!row.savedMap[row.network.ssid])

    signal connectRequested()
    signal forgetRequested()

    function signalIcon(signal) {
        const s = Number(signal) || 0;
        if (s <= 0) return Icons.signalWifi0;
        if (s < 30) return Icons.signalWifi1;
        if (s < 55) return Icons.signalWifi2;
        if (s < 80) return Icons.signalWifi3;
        return Icons.signalWifi4;
    }

    function securityLabel(sec) {
        if (!sec || sec === "" || sec === "--")
            return "Open";
        return sec;
    }

    function isSecure(sec) {
        return !!sec && sec !== "" && sec !== "--";
    }

    height: 50

    HoverHandler { id: rowHover }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Dimensions.radius.medium
        color: row.hovered ? Colors.stateLayer(Colors.onSurface, 0.06) : "transparent"
        border.width: row.connected ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.35)
        Behavior on color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        width: 2; height: 18; radius: 1
        visible: row.connected
        color: Colors.primary
    }

    Rectangle {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 32; height: 32; radius: 10
        color: row.connected ? Colors.primaryContainer : Colors.surfaceContainerHigh
        Text {
            anchors.centerIn: parent
            text: row.signalIcon(row.network.signal)
            color: row.connected ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.medium
        }
    }

    Column {
        anchors {
            left: parent.left; leftMargin: 52
            right: parent.right; rightMargin: 64
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
            width: parent.width
            text: row.network.ssid || "Unknown network"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            font.weight: row.connected ? Typography.weight.bold : Typography.weight.medium
            elide: Text.ElideRight
        }

        Row {
            spacing: 4
            Text {
                visible: row.isSecure(row.network.security)
                text: Icons.lock
                color: row.connected ? Colors.primary : Colors.onSurfaceVariant
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.small
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: {
                    if (row.connected) return "Connected";
                    let s = row.securityLabel(row.network.security);
                    if (row.saved) s += " · Saved";
                    return s;
                }
                color: row.connected ? Colors.primary : Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }
        }
    }

    Text {
        anchors { right: parent.right; rightMargin: row.hovered && row.saved ? 40 : 10; verticalCenter: parent.verticalCenter }
        visible: !(row.hovered && row.saved)
        text: (row.network.signal || 0) + "%"
        color: Colors.onSurfaceVariant
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
    }

    MouseArea {
        anchors.fill: parent
        anchors.rightMargin: row.hovered && row.saved ? 36 : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.connectRequested()
    }

    IconButton {
        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        icon: Icons.trash
        iconSize: Dimensions.icon.medium
        visible: row.hovered && row.saved && !row.connected
        onClicked: row.forgetRequested()
    }
}
