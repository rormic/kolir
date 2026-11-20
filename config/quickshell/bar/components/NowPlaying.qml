import "../../theme"
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Now playing: expanding media island.
//
// Collapsed it is an info chip: cover thumbnail, "Artist – Title", and a
// thin neon progress line at the bottom (the "playing" indicator — it
// moves while playing, dims and freezes on pause). On hover the island
// grows, the text condenses and transport buttons (prev / play-pause /
// next) slide in. Clicking the body toggles playback; the wheel skips
// tracks.
Surface {
    id: root

    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool interactive: hasPlayer && player.canControl
    readonly property bool expanded: hovered && interactive
    readonly property string trackText: player
        ? ((player.trackArtist ? player.trackArtist + " – " : "") + (player.trackTitle || ""))
        : ""

    // Set from Bar.qml: hidden on narrow screens.
    property bool enabled: true
    visible: enabled && hasPlayer && trackText !== ""

    readonly property bool hovered: _hover.hovered

    // Collapsed vs hovered text viewport widths. The island grows by
    // roughly the amount the text condenses, so it barely shifts when the
    // buttons slide in.
    readonly property int textMaxWidth: 150
    readonly property int textCondensedWidth: 110
    readonly property int horizontalPadding: Dimensions.padding.chipHorizontal

    readonly property bool progressSupported: hasPlayer
        && player.lengthSupported
        && player.positionSupported
        && player.length > 0

    // 0..1 position in the current track. `position` does not update
    // reactively; the poll Timer below emits its change signal while
    // playing so this binding re-reads the fresh value.
    readonly property real progress: progressSupported
        ? Math.max(0, Math.min(1, player.position / player.length))
        : 0

    readonly property bool artReady: hasPlayer
        && player.trackArtUrl !== ""
        && artImage.status === Image.Ready

    // Optimistic playback state. Some players (Firefox/Zen) never update
    // PlaybackStatus, and quickshell's togglePlaying() then keeps sending
    // Pause and can never resume. We flip this flag ourselves, send raw
    // MPRIS Play/Pause, and resync whenever the player reports a real
    // state change.
    property bool assumedPlaying: false

    implicitHeight: Dimensions.control.height
    implicitWidth: content.implicitWidth + horizontalPadding * 2
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // Neon border on hover
    borderColor: hovered
        ? Colors.withAlpha(Colors.primary, 0.55)
        : Colors.withAlpha(Colors.outlineVariant, 0.18)

    Behavior on borderColor {
        ColorAnimation { duration: 150 }
    }

    scale: hovered ? 1.04 : 1.0

    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function togglePlaying() {
        if (!interactive)
            return;

        const action = assumedPlaying ? "Pause" : "Play";
        assumedPlaying = !assumedPlaying;

        controlProc.command = [
            "busctl", "--user", "call", player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            action
        ];
        controlProc.running = true;
    }

    function syncAssumedState() {
        assumedPlaying = hasPlayer ? player.isPlaying : false;
    }

    function nextTrack() {
        if (hasPlayer && player.canGoNext)
            player.next();
    }

    function prevTrack() {
        if (hasPlayer && player.canGoPrevious)
            player.previous();
    }

    // The marquee should only run while the text actually overflows the
    // viewport (and never while the island is hidden). Width changes come
    // from Behaviors, so this is called per animation frame and must not
    // restart an already running loop.
    function syncMarquee() {
        const overflow = visible && textLabel.implicitWidth > viewport.width;

        if (overflow) {
            if (!marquee.running)
                marquee.restart();
        } else {
            marquee.stop();
            textLabel.x = 0;
        }
    }

    onTrackTextChanged: {
        textLabel.x = 0;
        marquee.stop();
        syncMarquee();
    }

    onVisibleChanged: syncMarquee()
    onExpandedChanged: syncMarquee()
    onPlayerChanged: syncAssumedState()

    IpcHandler {
        target: "nowPlaying"

        function playPause(): void {
            root.togglePlaying();
        }

        function next(): void {
            root.nextTrack();
        }

        function previous(): void {
            root.prevTrack();
        }
    }

    // Body: click toggles playback, wheel skips tracks. The layout is
    // parented to the MouseArea so wheels over the transport buttons
    // still propagate here, while button clicks stay on the buttons.
    MouseArea {
        id: body

        anchors.fill: parent
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: root.togglePlaying()

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                root.nextTrack();
            else if (wheel.angleDelta.y < 0)
                root.prevTrack();
        }

        Item {
            id: content

            anchors.left: parent.left
            anchors.leftMargin: root.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            height: Dimensions.control.height
            implicitWidth: controlsSlot.x + controlsSlot.width

            // Dim while paused, unless hovered for interacting.
            opacity: root.assumedPlaying
                ? 1.0
                : (root.hovered ? 1.0 : 0.6)

            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            // Cover thumbnail, icon fallback while missing.
            Item {
                id: coverSlot

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18

                Rectangle {
                    anchors.fill: parent
                    radius: Dimensions.radius.small
                    color: Colors.stateLayer(Colors.primary, 0.12)
                    visible: !root.artReady
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.artReady
                    text: Icons.musicNote
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: 12
                }

                Rectangle {
                    id: artClip

                    anchors.fill: parent
                    radius: Dimensions.radius.small
                    color: "transparent"
                    clip: true
                    opacity: root.artReady ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    Image {
                        id: artImage

                        anchors.fill: parent
                        source: root.hasPlayer ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
            }

            // Clipped text viewport; marquee for overflowing titles.
            Item {
                id: viewport

                anchors.left: coverSlot.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                clip: true
                width: Math.min(textLabel.implicitWidth,
                    root.expanded ? root.textCondensedWidth : root.textMaxWidth)

                Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                onWidthChanged: root.syncMarquee()

                Text {
                    id: textLabel

                    anchors.verticalCenter: parent.verticalCenter
                    text: root.trackText
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }

                // Marquee: rest, scroll through the title, rest, slide back.
                SequentialAnimation {
                    id: marquee

                    loops: Animation.Infinite

                    PauseAnimation { duration: 2000 }

                    NumberAnimation {
                        target: textLabel
                        property: "x"
                        from: 0
                        to: viewport.width - textLabel.implicitWidth
                        duration: Math.max(2500, (textLabel.implicitWidth - viewport.width) * 55)
                        easing.type: Easing.InOutSine
                    }

                    PauseAnimation { duration: 2000 }

                    NumberAnimation {
                        target: textLabel
                        property: "x"
                        from: viewport.width - textLabel.implicitWidth
                        to: 0
                        duration: 700
                        easing.type: Easing.InQuad
                    }
                }
            }

            // Transport buttons, revealed as the island expands on hover.
            Item {
                id: controlsSlot

                anchors.left: viewport.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                clip: true
                width: root.expanded ? controlsRow.implicitWidth + 6 : 0
                opacity: root.expanded ? 1 : 0

                Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }

                Row {
                    id: controlsRow

                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        icon: Icons.skipPrevious
                        iconSize: Dimensions.icon.medium
                        iconColor: Colors.onSurfaceVariant
                        opacity: root.hasPlayer && root.player.canGoPrevious ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        onClicked: root.prevTrack()
                    }

                    IconButton {
                        icon: root.assumedPlaying ? Icons.pause : Icons.playArrow
                        iconSize: Dimensions.icon.medium
                        iconColor: Colors.primary

                        onClicked: root.togglePlaying()
                    }

                    IconButton {
                        icon: Icons.skipNext
                        iconSize: Dimensions.icon.medium
                        iconColor: Colors.onSurfaceVariant
                        opacity: root.hasPlayer && root.player.canGoNext ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        onClicked: root.nextTrack()
                    }
                }
            }
        }
    }

    // Neon progress bar, in the style of the Volume chip.
    Rectangle {
        x: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: (parent.width - 12) * root.progress
        height: 2
        radius: 1
        visible: root.progressSupported
        color: root.assumedPlaying
            ? Colors.withAlpha(Colors.primary, 0.75)
            : Colors.withAlpha(Colors.primary, 0.3)

        Behavior on width {
            NumberAnimation { duration: 800; easing.type: Easing.OutCubic }
        }

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    // `position` does not update reactively, so emit its change signal once
    // per second while playing (the pattern recommended by the Quickshell
    // MprisPlayer docs).
    Timer {
        running: root.visible && root.hasPlayer && root.assumedPlaying
        interval: 1000
        repeat: true
        triggeredOnStart: true

        onTriggered: root.player.positionChanged()
    }

    // Raw MPRIS control. quickshell's play()/pause() short-circuit when the
    // reported state already matches, which never happens for players that
    // lie about PlaybackStatus, so the D-Bus methods are called directly.
    Process {
        id: controlProc

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("NowPlaying: MPRIS control error:", text.trim());
            }
        }

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("NowPlaying: MPRIS control call failed, exit code", code);
        }
    }

    // Crossfade the cover on track changes, including players that keep
    // reusing the same art URL (no reload means no fade otherwise), and
    // follow real playback state changes from well-behaved players.
    Connections {
        target: root.player

        function onPostTrackChanged() {
            coverFadeIn.restart();
        }

        function onPlaybackStateChanged() {
            root.syncAssumedState();
        }
    }

    NumberAnimation {
        id: coverFadeIn

        target: artImage
        property: "opacity"
        from: 0
        to: 1
        duration: 350
        easing.type: Easing.OutCubic
    }

    HoverHandler { id: _hover }

    Component.onCompleted: {
        syncAssumedState();
        syncMarquee();
    }
}
