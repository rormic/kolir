import QtQuick
import "../theme"

// Material 3 Expressive slider: a thick capsule track split by a vertical
// handle, with a stop indicator dot at the end of the inactive track.
Item {
    id: slider

    property real value: 0
    property bool muted: false
    property bool interactive: true

    signal moved(real value)
    signal dragStarted(real value)
    signal dragUpdated(real value)
    signal wheelMoved(real value)

    implicitHeight: 32
    implicitWidth: 200
    opacity: slider.interactive ? 1.0 : 0.45

    readonly property int trackHeight: 16
    readonly property int handleWidth: 4
    readonly property int handleHeight: 24
    readonly property int gap: 4
    readonly property int dotSize: 4
    readonly property int dotInset: 6

    readonly property real clampedValue: Math.max(0, Math.min(100, slider.value))

    // The handle travels between the two ends of the track, keeping half a
    // handle width of inset on each side.
    readonly property real travel: Math.max(0, slider.width - slider.handleWidth)
    readonly property real handleCenter: slider.handleWidth / 2
        + slider.travel * slider.clampedValue / 100
    readonly property real handleX: slider.handleCenter - slider.handleWidth / 2

    readonly property real activeWidth: Math.max(0, slider.handleX - slider.gap)
    readonly property real inactiveStart: Math.min(slider.width, slider.handleX + slider.handleWidth + slider.gap)
    readonly property real inactiveWidth: Math.max(0, slider.width - slider.inactiveStart)

    readonly property color activeColor: slider.muted
        ? Colors.withAlpha(Colors.error, 0.8)
        : Colors.primary

    // Filled part of the track. Rounded on the left edge, flat on the handle
    // side so the split meets the gap cleanly.
    Rectangle {
        id: activeTrack

        x: 0
        y: (slider.height - height) / 2
        width: slider.activeWidth
        height: slider.trackHeight
        visible: width > 0
        color: slider.activeColor
        topLeftRadius: Math.min(slider.trackHeight / 2, width / 2)
        bottomLeftRadius: Math.min(slider.trackHeight / 2, width / 2)
        topRightRadius: 0
        bottomRightRadius: 0

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    // Empty part of the track. Flat on the handle side, rounded on the far end.
    Rectangle {
        id: inactiveTrack

        x: slider.inactiveStart
        y: (slider.height - height) / 2
        width: slider.inactiveWidth
        height: slider.trackHeight
        visible: width > 0
        color: Colors.surfaceContainerHighest
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: Math.min(slider.trackHeight / 2, width / 2)
        bottomRightRadius: Math.min(slider.trackHeight / 2, width / 2)
    }

    // The vertical handle sits in the gap between the two track halves.
    Rectangle {
        id: handle

        x: slider.handleX
        y: (slider.height - slider.handleHeight) / 2
        width: slider.handleWidth
        height: slider.handleHeight
        radius: slider.handleWidth / 2
        color: Colors.onSurface
    }

    // Stop indicator at the end of the inactive track.
    Rectangle {
        id: stopIndicator

        x: slider.width - slider.dotSize - slider.dotInset
        y: (slider.height - slider.dotSize) / 2
        width: slider.dotSize
        height: slider.dotSize
        radius: slider.dotSize / 2
        color: slider.activeColor
        opacity: 0.8
        visible: slider.inactiveWidth > slider.dotSize + slider.dotInset + 2
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: slider.interactive
        hoverEnabled: true
        cursorShape: slider.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        // Convert pointer X to a value using the handle's travel range, so
        // the handle center follows the cursor at both ends.
        function posToValue(mouseX) {
            const travel = slider.travel;
            if (travel <= 0)
                return 0;
            return Math.max(0, Math.min(100,
                (mouseX - slider.handleWidth / 2) / travel * 100));
        }

        onPressed: mouse => {
            const v = area.posToValue(mouse.x);
            slider.value = v;
            slider.dragStarted(v);
        }

        onMouseXChanged: {
            if (!pressed)
                return;
            const v = area.posToValue(mouseX);
            slider.value = v;
            slider.dragUpdated(v);
        }

        onWheel: wheel => {
            if (!slider.interactive)
                return;
            const delta = wheel.angleDelta.y;
            if (delta === 0)
                return;
            const step = 2;
            const next = Math.max(0, Math.min(100, slider.value + (delta > 0 ? step : -step)));
            wheel.accepted = true;
            slider.value = next;
            slider.wheelMoved(next);
        }

        onReleased: mouse => {
            const v = area.posToValue(mouse.x);
            slider.value = v;
            slider.moved(v);
        }
    }
}
