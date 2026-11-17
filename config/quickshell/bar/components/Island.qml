import QtQuick
import "../../theme"

// Material 3 island container: a rounded tonal surface for bar grouping.
// Only bottom corners are rounded — the top edge is flush with the screen.
Item {
    id: root

    property color surfaceColor: Colors.withAlpha(Colors.surfaceContainer, 0.88)
    property int bottomRadius: Dimensions.radius.extraLarge

    default property alias content: inner.data

    clip: true

    Rectangle {
        id: bg
        x: 0
        y: -bottomRadius
        width: parent.width
        height: parent.height + bottomRadius
        color: root.surfaceColor
        radius: root.bottomRadius

        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
