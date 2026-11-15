import QtQuick
import "../../theme"

// Material 3 icon button — neon hover: icon goes primary, border appears.
Item {
    id: root

    property string icon: ""
    property int iconSize: Dimensions.icon.large
    property color iconColor: Colors.onSurface
    property color containerColor: "transparent"
    property bool active: false

    signal clicked()

    implicitWidth: Dimensions.control.iconButton
    implicitHeight: Dimensions.control.iconButton

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    readonly property alias iconItem: iconLabel

    scale: root.pressed ? 0.88 : root.hovered ? 1.08 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    // Background + neon border ring on hover
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.active
            ? Colors.primary
            : root.pressed
                ? Colors.stateLayer(Colors.onSurface, 0.14)
                : root.hovered
                    ? Colors.stateLayer(Colors.onSurface, 0.07)
                    : root.containerColor
        border.width: root.hovered && !root.active ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.6)

        Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }

    Text {
        id: iconLabel
        anchors.centerIn: parent
        text: root.icon
        color: root.active ? Colors.onPrimary : (root.hovered ? Colors.primary : root.iconColor)
        font.family: Typography.iconFont
        font.pixelSize: root.iconSize
        font.weight: Font.Normal
        Behavior on color { ColorAnimation { duration: 130 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
