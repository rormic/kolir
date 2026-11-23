import QtQuick
import QtQuick.Shapes
import "../../../theme"
import "TrackText.js" as TrackText

// Material 3 wavy progress bar for Now Playing media controls.
// Features an animated sine wave on the played section (or full line for live streams),
// a Material 3 vertical pill scrubber thumb, solid base track, and interactive seeking with drag feedback.
Item {
    id: root

    property real progress: 0
    property real position: 0
    property real length: 0
    property bool playing: false

    property color indicatorColor: Colors.onSurface
    property color trackColor: Colors.withAlpha(Colors.onSurface, 0.25)

    signal seekRequested(real ratio)

    implicitHeight: 22

    readonly property bool isLive: (!root.length || isNaN(root.length) || root.length <= 0)

    // Optimistic progress during user drag
    property real dragProgress: -1

    readonly property real effectiveProgress: dragProgress >= 0
        ? dragProgress
        : (isLive ? 1.0 : Math.max(0, Math.min(1, (!root.progress || isNaN(root.progress)) ? 0 : root.progress)))

    // Wave parameters (Material 3 spec)
    readonly property real amplitude: 3.5
    readonly property int wavelength: 28
    readonly property real thickness: 3.0

    property real phase: 0
    property var wavePoints: []

    // Continuous smooth wave animation while playing
    NumberAnimation on phase {
        from: 0
        to: root.wavelength
        duration: 900
        loops: Animation.Infinite
        running: root.playing && (root.effectiveProgress > 0.02 || root.isLive)
    }

    function rebuildWave() {
        const w = root.width;
        if (w <= 0) {
            wavePoints = [];
            return;
        }

        const activeW = root.isLive ? w : Math.max(0, Math.min(w, w * root.effectiveProgress));

        if (!root.playing || activeW < 4) {
            wavePoints = [];
            return;
        }

        const cy = root.height / 2;
        const pts = [];
        const step = 1.5;
        for (let x = 0; x <= activeW; x += step) {
            const y = cy + root.amplitude * Math.sin((x - root.phase) * 2 * Math.PI / root.wavelength);
            pts.push(Qt.point(x, y));
        }
        wavePoints = pts;
    }

    onPhaseChanged: rebuildWave()
    onEffectiveProgressChanged: rebuildWave()
    onPlayingChanged: rebuildWave()
    onWidthChanged: rebuildWave()
    Component.onCompleted: rebuildWave()

    // --- Base track: ALWAYS visible across full width (never disappears) ---
    Rectangle {
        id: baseTrack

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        height: root.thickness
        radius: root.thickness / 2
        color: root.trackColor
    }

    // --- Flat active segment (when paused or wave too short) ---
    Rectangle {
        id: flatActiveSegment

        readonly property real activeW: root.isLive ? root.width : root.width * root.effectiveProgress

        visible: (!root.playing || root.wavePoints.length <= 1) && activeW > 0
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.width, activeW)
        height: root.thickness
        radius: root.thickness / 2
        color: root.indicatorColor
    }

    // --- Animated Wavy active segment (when playing) ---
    Shape {
        id: waveShape

        anchors.fill: parent
        visible: root.playing && root.wavePoints.length > 1
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

    // --- Material 3 Vertical Pill Scrubber Thumb ---
    Rectangle {
        id: thumb

        readonly property real thumbX: Math.max(
            0, Math.min(root.width - width, root.width * root.effectiveProgress - width / 2))

        visible: !root.isLive
        x: thumbX
        anchors.verticalCenter: parent.verticalCenter
        width: scrubberArea.containsMouse || scrubberArea.pressed ? 5 : 3.5
        height: scrubberArea.containsMouse || scrubberArea.pressed ? 16 : 13
        radius: width / 2
        color: root.indicatorColor
        z: 10

        Behavior on width {
            NumberAnimation { duration: Motion.scale; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: Motion.scale; easing.type: Easing.OutCubic }
        }
    }

    Timer {
        id: resetDragTimer

        interval: 350
        repeat: false
        onTriggered: root.dragProgress = -1
    }

    // --- Seeking mouse area ---
    MouseArea {
        id: scrubberArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isLive ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !root.isLive

        onPressed: mouse => {
            resetDragTimer.stop();
            root.dragProgress = Math.max(0, Math.min(1, mouse.x / width));
        }

        onPositionChanged: mouse => {
            if (pressed) {
                root.dragProgress = Math.max(0, Math.min(1, mouse.x / width));
            }
        }

        onReleased: mouse => {
            const ratio = Math.max(0, Math.min(1, mouse.x / width));
            root.dragProgress = ratio;
            root.seekRequested(ratio);
            resetDragTimer.restart();
        }

        onCanceled: {
            root.dragProgress = -1;
        }
    }
}
