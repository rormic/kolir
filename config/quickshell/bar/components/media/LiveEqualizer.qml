pragma ComponentBehavior: Bound

import QtQuick
import "../../../theme"

// Tiny animated signal bars for a live broadcast's status row.
//
// The heights are bound to a continuously animated phase, so pausing playback
// collapses them to a resting line without leaving a frozen frame behind (a
// property animation on `height` would keep its last value when stopped).
Item {
    id: root

    property bool playing: false
    // Stops the driver while the card is collapsed; the bars are invisible
    // then, and the island should not keep animating off-screen.
    property bool active: true
    property color color: Colors.error

    readonly property int barCount: 5
    readonly property int barWidth: 2
    readonly property int barSpacing: 2
    readonly property real restHeight: 3
    readonly property real maxHeight: 14

    implicitWidth: barCount * barWidth + (barCount - 1) * barSpacing
    implicitHeight: maxHeight
    width: implicitWidth
    height: implicitHeight

    property real phase: 0

    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 1300
        loops: Animation.Infinite
        running: root.playing && root.active && root.visible
    }

    Repeater {
        model: root.barCount

        Rectangle {
            required property int index

            x: index * (root.barWidth + root.barSpacing)
            width: root.barWidth
            height: root.playing
                ? root.restHeight + (root.maxHeight - root.restHeight)
                    * (0.5 + 0.5 * Math.sin(root.phase + index * 1.15))
                : root.restHeight
            y: root.implicitHeight - height
            radius: root.barWidth / 2
            color: root.color
            opacity: 0.85

            // Only smooth the collapse into the paused state; the playing
            // heights arrive every frame and must not lag behind the phase.
            Behavior on height {
                enabled: !root.playing
                NumberAnimation {
                    duration: Motion.fade
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.emphasizedAccelerateCurve
                }
            }
        }
    }
}
