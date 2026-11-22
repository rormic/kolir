import QtQuick
import "../../services"
import "../../theme"

// Bar bell for the notification center. The unread count is a badge over the
// icon; while do-not-disturb is on the glyph switches to notifications_off.
// Clicking toggles the center panel (Bar owns the sheet and the mutual
// exclusion with the other embedded sheets).
Item {
    id: root

    signal activated()

    // Highlight while the center panel is open (mirrors the other chips).
    property bool active: false

    implicitWidth: Dimensions.control.iconButton
    implicitHeight: Dimensions.control.iconButton

    readonly property int count: NotificationService.unread
    readonly property bool dnd: NotificationService.dnd

    IconButton {
        anchors.fill: parent
        icon: root.dnd ? Icons.notificationsOff : Icons.notifications
        iconSize: Dimensions.icon.large
        iconColor: root.dnd ? Colors.onSurfaceVariant : Colors.onSurface
        active: root.active && !root.dnd
        onClicked: root.activated()
    }

    // Unread badge. It sits partly over the bell corner, like the tray/menu
    // badges, and keeps the bar strip opaque behind it.
    Rectangle {
        visible: root.count > 0
        x: root.width - width + 4
        y: -3
        width: Math.max(15, label.implicitWidth + 6)
        height: 15
        radius: height / 2
        color: Colors.primary

        Text {
            id: label

            anchors.centerIn: parent
            text: root.count > 99 ? "99+" : root.count
            color: Colors.onPrimary
            font.family: Typography.barFont
            font.pixelSize: 9
            font.weight: Typography.weight.bold
        }
    }
}
