import QtQuick
import "../../../theme"

// One Bluetooth codec chip in the sound popup. The caller resolves the label
// and whether the profile is the active one.
Rectangle {
    id: root

    property string label: ""
    property bool active: false

    signal activated()

    readonly property bool hovered: chipHover.hovered

    width: chipText.implicitWidth + 20
    height: 26
    radius: Dimensions.radius.full
    color: root.active
        ? Colors.primaryContainer
        : root.hovered
            ? Colors.stateLayer(Colors.primary, 0.12)
            : Colors.surfaceContainerLowest
    border.width: 1
    border.color: root.active
        ? Colors.withAlpha(Colors.primary, 0.7)
        : Colors.withAlpha(Colors.outlineVariant, 0.35)

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    HoverHandler { id: chipHover }

    Text {
        id: chipText

        anchors.centerIn: parent
        text: root.label
        color: root.active
            ? Colors.onPrimaryContainer
            : Colors.onSurfaceVariant
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
        font.weight: root.active
            ? Typography.weight.bold
            : Typography.weight.medium
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !root.active
        onClicked: root.activated()
    }
}
