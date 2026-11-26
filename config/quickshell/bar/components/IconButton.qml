import QtQuick
import "../../theme"

// Material 3 icon button — neon hover: icon goes primary, border appears.
Item {
    id: root

    property string icon: ""
    property int iconSize: Dimensions.icon.large
    property color iconColor: Colors.onSurface
    // Hover tint. The now-playing island overrides it so its transport icons
    // stay legible on a cover-derived container.
    property color iconHoverColor: Colors.primary
    // Press/hover state layer tint under the icon.
    property color stateColor: Colors.onSurface
    property color containerColor: "transparent"
    property bool active: false

    // Optical fine-tuning: Material Symbols glyphs do not sit perfectly in the
    // middle of their line box, so icons can be nudged for a centered look.
    property real iconOffsetX: 0
    property real iconOffsetY: 0

    signal clicked()

    implicitWidth: Dimensions.control.iconButton
    implicitHeight: Dimensions.control.iconButton

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    readonly property alias iconItem: iconLabel

    scale: root.pressed ? 0.88 : root.hovered ? 1.08 : 1.0
    // Small interactive control scale: the M3 fast spatial spring.
    Behavior on scale {
        SpringAnimation {
            spring: Motion.spatialSpringFast
            damping: Motion.spatialSpringFastDamping
            epsilon: Motion.springScaleEpsilon
        }
    }

    // Background + neon border ring on hover
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.active
            ? Colors.primary
            : root.pressed
                ? Colors.stateLayer(root.stateColor, 0.14)
                : root.hovered
                    ? Colors.stateLayer(root.stateColor, 0.07)
                    : root.containerColor
        border.width: root.hovered && !root.active ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.6)

        Behavior on color {
            ColorAnimation {
                duration: Motion.press
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    Text {
        id: iconLabel
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.iconOffsetX
        anchors.verticalCenterOffset: root.iconOffsetY
        text: root.icon
        color: root.active ? Colors.onPrimary : (root.hovered ? root.iconHoverColor : root.iconColor)
        font.family: Typography.iconFont
        font.pixelSize: root.iconSize
        font.weight: Font.Normal
        Behavior on color {
            ColorAnimation {
                duration: Motion.press
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
