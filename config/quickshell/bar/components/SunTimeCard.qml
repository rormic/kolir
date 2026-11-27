import QtQuick
import "../../theme"

// Compact read-only solar time used by the night-light sheet and the
// Appearance page. The glyph carries the meaning (day starts, night starts),
// so the card needs no caption text next to the value.
Rectangle {
    id: root

    property string icon: ""
    property string value: "—"

    implicitWidth: 150
    implicitHeight: 36
    opacity: root.value === "—" ? 0.6 : 1.0
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerLowest
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.3)

    Row {
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: Colors.primary
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.medium
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            color: root.value === "—" ? Colors.onSurfaceVariant : Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: Typography.weight.bold
        }
    }
}
