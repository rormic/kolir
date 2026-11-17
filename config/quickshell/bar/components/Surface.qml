import QtQuick
import "../../theme"

// Neon accent surface: dark opaque base, thin accent border.
Rectangle {
    id: root

    property color surfaceColor: Colors.surfaceContainerHigh
    property color borderColor: Colors.withAlpha(Colors.outlineVariant, 0.18)
    property int borderWidth: 1

    default property alias content: inner.data

    color: root.surfaceColor
    radius: Dimensions.radius.large
    border.width: root.borderWidth
    border.color: root.borderColor
    clip: true

    Behavior on color {
        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
