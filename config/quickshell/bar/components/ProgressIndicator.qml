import QtQuick
import QtQuick.Shapes
import "../../theme"

// Material 3 linear progress indicator.
//
// Spec metrics (Material 3, "Progress indicators"):
//   - 4dp track thickness
//   - 4dp gap between the active and inactive segments
//   - 4dp stop indicator at the trailing end, 4dp inset from the track
//   - wavy variant: 3dp amplitude, 40dp wavelength
//
// The flat variant is the default. `wavy` turns the active segment into an
// animated sine wave, which fits roomy surfaces like the OSDs; the bar pills
// keep the flat variant because they are only 24dp tall.
Item {
    id: root

    // 0..100, same unit as AudioService.volume / BrightnessService.value.
    property real value: 0

    property color indicatorColor: Colors.primary
    property color trackColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)

    property int thickness: Dimensions.progress.thickness
    property int gap: Dimensions.progress.gap

    // Material 3 stop indicator dot at the end of the inactive segment.
    property bool stopIndicator: true
    property int stopIndicatorSize: Dimensions.progress.stopIndicator

    // Wave metrics. The wave is drawn only on the active segment; the
    // inactive segment and the stop indicator stay flat, as in the spec.
    property bool wavy: false
    property real amplitude: Dimensions.progress.waveAmplitude
    property int wavelength: Dimensions.progress.wavelength
    property bool animated: true
    // Extra gate for the wave animation, so a hidden OSD does not keep
    // rebuilding the wave path. The bar pills stay flat and ignore it.
    property bool playing: true

    // Wave phase and the generated polyline. The path is rebuilt when the
    // phase, the value or any wave metric changes.
    property real phase: 0
    property var wavePoints: []

    implicitHeight: root.wavy ? root.thickness + root.amplitude * 2 : root.thickness

    readonly property real progress: Math.max(0, Math.min(1, root.value / 100))
    readonly property bool complete: root.progress >= 0.999

    // Space reserved at the trailing edge for one gap, the dot and the
    // trailing gap, so the inactive segment never runs into the dot.
    readonly property real reservedEnd: root.stopIndicator
        ? root.stopIndicatorSize + root.gap * 2
        : 0

    readonly property real activeWidth: root.complete
        ? root.width
        : Math.min(root.width, Math.max(root.progress > 0 ? root.thickness : 0,
                                       root.progress * Math.max(0, root.width - root.reservedEnd)))

    readonly property real inactiveX: root.progress > 0 && !root.complete
        ? Math.min(root.width, root.activeWidth + root.gap)
        : 0
    readonly property real inactiveEnd: Math.max(0, root.width - root.reservedEnd)
    readonly property real inactiveWidth: root.complete
        ? 0
        : Math.max(0, root.inactiveEnd - root.inactiveX)
    readonly property bool showStop: root.stopIndicator && !root.complete
        && root.width >= root.reservedEnd + root.gap

    // The wave needs room for two round caps; shorter active segments are
    // drawn as a plain dot by the flat fill instead.
    readonly property bool waveVisible: root.wavy && !root.complete
        && root.activeWidth > root.thickness + 1

    Behavior on value {
        enabled: root.animated
        NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
    }

    // Build the active wave as a polyline. The sine runs at full amplitude
    // right up to the round caps, so the first and last humps are the same
    // size as the rest and the ends move with the animation. The caps come
    // from ShapePath.RoundCap, not from an amplitude envelope.
    function rebuildWave() {
        if (!root.waveVisible || root.wavelength <= 0) {
            root.wavePoints = [];
            return;
        }

        const aw = Math.min(root.activeWidth, root.width);
        const radius = root.thickness / 2;
        const start = radius;
        const end = Math.max(start, aw - radius);
        const cy = root.height / 2;
        const pts = [];

        for (let x = start; x <= end; x += 0.5) {
            const y = cy + root.amplitude
                * Math.sin((x - root.phase) * 2 * Math.PI / root.wavelength);
            pts.push(Qt.point(x, y));
        }

        const lastY = cy + root.amplitude
            * Math.sin((end - root.phase) * 2 * Math.PI / root.wavelength);
        pts.push(Qt.point(end, lastY));
        root.wavePoints = pts;
    }

    onPhaseChanged: rebuildWave()
    onActiveWidthChanged: rebuildWave()
    onAmplitudeChanged: rebuildWave()
    onWavelengthChanged: rebuildWave()
    onThicknessChanged: rebuildWave()
    onWavyChanged: rebuildWave()
    onHeightChanged: rebuildWave()
    Component.onCompleted: rebuildWave()

    // The wave advances at one wavelength per second, matching the reference
    // implementation: in WavyProgressIndicator.kt waveSpeed is in dp/s and
    // defaults to `wavelength` ("Match to 1 wavelength per second"). For the
    // 40dp wavelength token that is 40dp/s, i.e. a 1000ms cycle.
    NumberAnimation on phase {
        from: 0
        to: root.wavelength
        duration: Motion.spin
        loops: Animation.Infinite
        running: root.wavy && root.animated && root.playing
            && root.progress > 0 && !root.complete
    }

    // Inactive track. It starts after the gap so the active and inactive
    // segments read as one bar broken by a 4dp gap.
    Rectangle {
        id: track

        visible: root.inactiveWidth > 0
        x: root.inactiveX
        anchors.verticalCenter: parent.verticalCenter
        width: root.inactiveWidth
        height: root.thickness
        radius: root.thickness / 2
        color: root.trackColor

        Behavior on width {
            NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
        }
    }

    // Flat active segment (also used at 100%, when the bar is complete).
    Rectangle {
        id: fill

        visible: !root.wavy || root.complete || !root.waveVisible
        width: root.activeWidth
        height: root.thickness
        anchors.verticalCenter: parent.verticalCenter
        radius: root.thickness / 2
        color: root.indicatorColor

        Behavior on width {
            NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
        }
    }

    // Wavy active segment. A vector polyline instead of a clipped canvas:
    // the stroke keeps clean round caps and does not show clip artifacts.
    Shape {
        width: root.activeWidth
        height: root.height
        visible: root.waveVisible && root.wavePoints.length > 1
        // CurveRenderer has native high-quality antialiasing; the default
        // GeometryRenderer leaves the stroke edges jagged.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.indicatorColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.wavePoints
            }
        }
    }

    // Material 3 stop indicator: a dot marking the end of the track.
    Rectangle {
        visible: root.showStop
        x: root.width - root.gap - root.stopIndicatorSize
        anchors.verticalCenter: parent.verticalCenter
        width: root.stopIndicatorSize
        height: root.stopIndicatorSize
        radius: root.stopIndicatorSize / 2
        color: root.indicatorColor
    }
}
