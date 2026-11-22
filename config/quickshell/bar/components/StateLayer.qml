import QtQuick
import "../../theme"

// Material 3 state layer: the hover/selected tint as its own translucent fill,
// fading in over an opaque container.
//
// Animating the container's `color` between an opaque base and
// `Colors.stateLayer(...)` also interpolates the alpha channel, so the colour
// passes through bright, still-opaque grey and the surface flashes once on
// hover-in and once on hover-out. Every tinted control uses this fill instead,
// so the fade is identical everywhere (rows, chips, buttons, device lists).
Rectangle {
    id: root

    // Whether the tint is shown; the opacity transition does the rest.
    property bool shown: false
    property color tint: Colors.primary
    // Alpha of the tint at full opacity, e.g. 0.14 for a settings row.
    property real strength: 0.12
    property int duration: Motion.hover

    anchors.fill: parent
    radius: parent && parent.radius !== undefined ? parent.radius : 0
    color: Colors.stateLayer(root.tint, root.strength)
    opacity: root.shown ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation {
            duration: root.duration
            easing.type: Easing.OutCubic
        }
    }
}
