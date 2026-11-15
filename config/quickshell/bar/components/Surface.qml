import QtQuick
import "../../theme"

// A tonal Material 3 surface: no bevels, no decorative borders.
// Extra children are placed inside `content` so they can use the full area.
Rectangle {
    id: root

    property color surfaceColor: Colors.surfaceContainerHigh
    property color borderColor: "transparent"
    property int borderWidth: 0

    default property alias content: inner.data

    color: root.surfaceColor
    radius: Dimensions.radius.large
    border.width: root.borderWidth
    border.color: root.borderColor
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
