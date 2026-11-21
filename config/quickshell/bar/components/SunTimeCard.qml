import QtQuick
import "../../theme"

// Compact read-only sunrise/sunset card used by the night-light popup.
Rectangle {
    id: root

    property string icon: ""
    property string caption: ""
    property string value: "—"

    implicitWidth: 150
    implicitHeight: 62
    opacity: root.value === "—" ? 0.6 : 1.0
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerLowest
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.3)

    Column {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 2

        Row {
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                color: Colors.primary
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.medium
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.caption
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                font.weight: Typography.weight.medium
            }
        }

        Text {
            text: root.value
            color: root.value === "—" ? Colors.onSurfaceVariant : Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: Typography.weight.bold
        }
    }
}
