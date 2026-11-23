import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets
import "../../services"
import "../../theme"
import "media"
import ".."

// Now Playing: Material 3 expanding media island with a poured bar notch.
//
// A single morphing card that starts as a compact pill inside the bar strip
// and smoothly grows vertically downward into a full Android 13/14-style
// media card.  The notch frame (surfaceContainerLow) pours out of the bar
// strip in sync, wrapping the card with shoulder arcs and rounded corners.
//
// Stage 1 — Idle:   muted "No media" pill, no notch.
// Stage 2 — Playing: compact pill in the bar, track text + play button.
// Stage 3 — Hover:   the pill morphs into the expanded card below the bar.
Item {
    id: root

    // Set from Bar.qml
    property bool enabled: true
    property int slotWidth: 0

    // State 3 toggle
    property bool expanded: false

    MprisController {
        id: controller

        pollActive: root.visible
    }

    CoverPalette {
        id: coverPalette

        artUrl: controller.trackCoverUrl
        active: root.visible && root.hasPlayer && controller.trackCoverUrl !== ""
    }

    readonly property var player: controller.player
    readonly property bool hasPlayer: controller.hasPlayer
    readonly property bool interactive: controller.interactive
    readonly property string trackTitle: controller.trackTitle
    readonly property string trackArtist: controller.trackArtist
    readonly property string trackText: controller.trackText
    readonly property string trackCoverUrl: controller.trackCoverUrl

    // Idle state: no player or no active metadata
    readonly property bool idle: !hasPlayer || trackText === ""

    // 1: Idle, 2: Compact Playing, 3: Expanded Playing
    readonly property int stateIndex: idle ? 1 : (expanded ? 3 : 2)

    visible: enabled

    // Dynamic cover palette with fallback to standard Colors
    readonly property bool paletteActive: coverPalette.paletteReady
    readonly property color foregroundColor: paletteActive
        ? coverPalette.containerTextColor
        : Colors.onSurface
    readonly property color accentColor: paletteActive
        ? coverPalette.accentColor
        : Colors.primary
    readonly property color accentTextColor: paletteActive
        ? coverPalette.accentTextColor
        : Colors.onPrimary
    readonly property color cardSurfaceColor: paletteActive
        ? coverPalette.containerColor
        : Colors.surfaceContainerHigh

    // Cover art source resolution
    readonly property string artSource: trackCoverUrl === ""
        ? ""
        : (trackCoverUrl.startsWith("/") ? "file://" + trackCoverUrl : trackCoverUrl)
    readonly property bool artReady: artSource !== "" && artImageCache.status === Image.Ready
    readonly property bool appIconReady: appIconCache.ready
    readonly property bool showNoteIcon: !artReady && !appIconReady

    // Hidden image / appIcon for status caching
    Image {
        id: artImageCache
        source: root.artSource
        visible: false
    }

    AppIcon {
        id: appIconCache
        appClass: root.player ? root.player.desktopEntry : ""
        visible: false
    }

    // Fixed width: strictly constant so there is NEVER any horizontal resize
    readonly property int fixedWidth: Math.max(340, Math.min(380, root.slotWidth > 0 ? root.slotWidth : 350))
    implicitWidth: fixedWidth
    implicitHeight: Dimensions.bar.height + (expanded ? (expandedBodyHeight + 40) : Math.max(0, notchDrop))

    // Notch metrics
    readonly property int notchShoulderRadius: 16
    readonly property int notchBottomRadius: 20

    // How far the expanded card body extends below the bar strip
    readonly property int expandedBodyHeight: 118

    // Single fluid expand driver: 0.0 (compact pill) -> 1.0 (expanded card)
    property real expandProgress: 0.0
    readonly property real targetExpandProgress: (root.stateIndex === 3) ? 1.0 : 0.0

    onTargetExpandProgressChanged: expandProgress = targetExpandProgress

    Behavior on expandProgress {
        NumberAnimation {
            duration: 320
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.2, 0, 0, 1]
        }
    }

    // The morphCard top y stays constant; height grows vertically downward.
    readonly property real cardY: (Dimensions.bar.height - Dimensions.control.height) / 2
    readonly property real cardHeight: Dimensions.control.height
        + root.expandProgress * root.expandedBodyHeight

    // The portion of the card that extends below the bar strip,
    // plus padding so the surfaceContainerLow frame is even on all sides.
    readonly property real notchDrop: Math.max(0,
        root.cardY + root.cardHeight - Dimensions.bar.height
        + 8 * root.expandProgress)
    readonly property real notchWidth: root.fixedWidth
    readonly property real notchX: root.x

    // Radius morphs from pill (half-height) to card corners
    readonly property real cardRadius: Dimensions.control.height / 2
        + root.expandProgress * (root.notchBottomRadius - Dimensions.control.height / 2)

    function openExpanded() {
        if (!root.idle) {
            root.expanded = true;
            root.forceActiveFocus();
        }
    }

    function closeExpanded() {
        root.expanded = false;
    }

    function toggleExpanded() {
        if (root.expanded)
            closeExpanded();
        else
            openExpanded();
    }

    IpcHandler {
        target: "media"

        function toggle() {
            root.toggleExpanded();
        }

        function open() {
            root.openExpanded();
        }

        function close() {
            root.closeExpanded();
        }
    }

    // If playback stops while expanded, collapse automatically
    onIdleChanged: {
        if (root.idle && root.expanded)
            root.closeExpanded();
    }

    Keys.onEscapePressed: event => {
        if (root.expanded) {
            root.closeExpanded();
            event.accepted = true;
        }
    }

    // Hover zone covering the bar slot and the downward pour
    Item {
        id: hoverZone

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
        width: root.fixedWidth + root.notchShoulderRadius * 2
        height: root.height
        z: 2

        HoverHandler {
            id: mainHover

            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop();
                    if (!root.idle)
                        root.expanded = true;
                } else if (!cardHover.hovered) {
                    closeTimer.restart();
                }
            }
        }
    }

    Timer {
        id: closeTimer

        interval: 450
        repeat: false
        onTriggered: {
            if (!mainHover.hovered && !cardHover.hovered)
                root.expanded = false;
        }
    }

    // SVG Notch path dipping smoothly down from the bar line
    readonly property string notchSvgPath: {
        const w = root.fixedWidth;
        const h = Math.max(0, root.notchDrop);
        if (h <= 0.5)
            return "";

        const sr = root.notchShoulderRadius;
        const cr = root.notchBottomRadius;
        const scale = (sr + cr > h) ? (h / (sr + cr)) : 1.0;
        const safeSr = Math.max(1.0, Math.min(sr * scale, w / 4));
        const safeCr = Math.max(1.0, Math.min(cr * scale, w / 4));
        const yShoulder = safeSr;
        const yCornerStart = h - safeCr;

        return `M ${-safeSr.toFixed(2)} 0 `
            + `A ${safeSr.toFixed(2)} ${safeSr.toFixed(2)} 0 0 1 0 ${yShoulder.toFixed(2)} `
            + `V ${yCornerStart.toFixed(2)} `
            + `A ${safeCr.toFixed(2)} ${safeCr.toFixed(2)} 0 0 0 ${safeCr.toFixed(2)} ${h.toFixed(2)} `
            + `H ${(w - safeCr).toFixed(2)} `
            + `A ${safeCr.toFixed(2)} ${safeCr.toFixed(2)} 0 0 0 ${w.toFixed(2)} ${yCornerStart.toFixed(2)} `
            + `V ${yShoulder.toFixed(2)} `
            + `A ${safeSr.toFixed(2)} ${safeSr.toFixed(2)} 0 0 1 ${(w + safeSr).toFixed(2)} 0 `
            + `Z`;
    }

    // The poured notch shape (melts from bar with surfaceContainerLow)
    Shape {
        id: notchShape

        anchors {
            left: parent.left
            right: parent.right
        }
        y: Dimensions.bar.height
        height: Math.max(0, root.notchDrop)
        visible: root.notchDrop > 0.5
        preferredRendererType: Shape.CurveRenderer
        z: 5

        ShapePath {
            fillColor: Colors.surfaceContainerLow
            strokeWidth: 0

            PathSvg {
                path: root.notchSvgPath
            }
        }
    }

    // --- State 1: Idle Pill (Visible when no music is active) ---
    Surface {
        id: idlePill

        anchors.horizontalCenter: parent.horizontalCenter
        y: (Dimensions.bar.height - Dimensions.control.height) / 2
        implicitHeight: Dimensions.control.height
        implicitWidth: root.fixedWidth
        radius: Dimensions.radius.full
        surfaceColor: Colors.surfaceContainerHigh
        borderColor: Colors.withAlpha(Colors.outlineVariant, 0.18)
        opacity: root.stateIndex === 1 ? 0.45 : 0.0
        visible: opacity > 0.001
        z: 6

        Behavior on opacity {
            NumberAnimation { duration: Motion.fade }
        }

        Row {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.musicNote
                color: Colors.onSurfaceVariant
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.small
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "No media"
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
            }
        }
    }

    // ================================================================
    // Single morphing card: pill ➜ expanded card in one continuous shape
    // ================================================================
    // ClippingRectangle clips children to the rounded corners so the
    // album art, scrim and content never poke past the card edge.
    ClippingRectangle {
        id: morphCard

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.fixedWidth - 16
        y: root.cardY
        height: root.cardHeight
        radius: root.cardRadius
        color: root.cardSurfaceColor

        opacity: root.stateIndex !== 1 ? 1.0 : 0.0
        visible: opacity > 0.001
        z: 8

        Behavior on opacity {
            NumberAnimation { duration: Motion.fade }
        }

        HoverHandler {
            id: cardHover

            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop();
                    if (!root.idle)
                        root.expanded = true;
                } else if (!mainHover.hovered) {
                    closeTimer.restart();
                }
            }
        }

        // Thin accent border on top of everything
        Rectangle {
            anchors.fill: parent
            radius: root.cardRadius
            color: "transparent"
            border.width: 1
            border.color: Colors.withAlpha(root.accentColor,
                0.25 * (1.0 - root.expandProgress) + 0.15 * root.expandProgress)
            z: 20
        }

        // Full album artwork background (fades in with expansion)
        Image {
            anchors.fill: parent
            source: root.artSource
            visible: root.artReady && root.expandProgress > 0.01
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            opacity: root.expandProgress
        }

        // Dark dimming scrim over artwork for readability
        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha(Colors.scrim, 0.50)
            opacity: root.expandProgress
            visible: root.artReady && opacity > 0.001
        }

        // Tint overlay with cover palette
        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha(root.cardSurfaceColor, 0.45)
            opacity: root.expandProgress
            visible: root.artReady && opacity > 0.001
        }

        // ==========================================
        // COMPACT CONTENT (top 24px, fades out early)
        // ==========================================
        Item {
            id: compactContent

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Dimensions.control.height
            opacity: Math.max(0, 1.0 - root.expandProgress * 2.5)
            visible: opacity > 0.001

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !root.expanded
                onClicked: root.openExpanded()
                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0)
                        controller.nextTrack();
                    else if (wheel.angleDelta.y < 0)
                        controller.prevTrack();
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 8
                spacing: Dimensions.media.coverSpacing

                // 18x18 cover thumbnail
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Dimensions.media.cover
                    height: Dimensions.media.cover

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Dimensions.media.coverRadius
                        color: Colors.withAlpha(root.accentColor, 0.14)

                        Text {
                            anchors.centerIn: parent
                            visible: root.showNoteIcon
                            text: Icons.musicNote
                            color: root.accentColor
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.small
                        }

                        AppIcon {
                            anchors.fill: parent
                            iconSize: Dimensions.media.cover
                            appClass: root.player ? root.player.desktopEntry : ""
                            fallbackIcon: ""
                            visible: !root.artReady && ready
                        }

                        Image {
                            anchors.fill: parent
                            source: root.artSource
                            visible: root.artReady
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                }

                // Single-line track text
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Dimensions.media.cover - Dimensions.media.coverSpacing - compactTransport.width - 12
                    text: root.trackText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.foregroundColor
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }

                // Compact play button
                Row {
                    id: compactTransport
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: controller.assumedPlaying ? Icons.pause : Icons.playArrow
                        iconSize: Dimensions.icon.medium
                        iconColor: root.accentColor
                        iconHoverColor: root.accentColor
                        stateColor: root.accentColor
                        onClicked: controller.togglePlaying()
                    }
                }
            }

            // Compact thin bottom progress line
            Rectangle {
                x: Dimensions.media.progressInset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Dimensions.media.progressBottomMargin
                width: Math.max(0, (parent.width - Dimensions.media.progressInset * 2) * controller.progress)
                height: Dimensions.media.progressThickness
                radius: Dimensions.media.progressThickness / 2
                visible: controller.progressSupported
                color: controller.assumedPlaying
                    ? Colors.withAlpha(root.accentColor, 0.75)
                    : Colors.withAlpha(root.accentColor, 0.3)
            }
        }

        // ==========================================
        // EXPANDED CONTENT (fills card, fades in)
        // ==========================================
        // Positioned so the visible part starts just below the bar strip.
        // barOffset = bar.height - morphCard.y ≈ 27px from morphCard top.
        Item {
            id: expandedContent

            // Start just below the bar strip line
            readonly property int barOffset: Dimensions.bar.height - root.cardY

            anchors.fill: parent
            opacity: Math.max(0, (root.expandProgress - 0.25) / 0.75)
            visible: opacity > 0.001

            // --- Top Row: Platform Badge + Audio Device Chip ---
            Item {
                id: topRow
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: expandedContent.barOffset + 4
                    leftMargin: 12
                    rightMargin: 12
                }
                height: 20

                // Platform / Player Badge on Left
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20
                    width: badgeContent.width + 14
                    radius: 10
                    color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.65)
                    border.width: 1
                    border.color: Colors.withAlpha(Colors.outlineVariant, 0.2)

                    Row {
                        id: badgeContent
                        anchors.centerIn: parent
                        spacing: 4

                        AppIcon {
                            id: badgeAppIcon
                            anchors.verticalCenter: parent.verticalCenter
                            iconSize: 13
                            appClass: root.player ? root.player.desktopEntry : ""
                            fallbackIcon: ""
                            visible: ready
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !badgeAppIcon.ready
                            text: Icons.musicNote
                            font.family: Typography.iconFont
                            font.pixelSize: 11
                            color: Colors.onSurface
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.player
                                ? (root.player.identity || root.player.desktopEntry || "Media")
                                : "Media"
                            font.family: Typography.barFont
                            font.pixelSize: 10
                            font.weight: Typography.weight.medium
                            color: Colors.onSurface
                            elide: Text.ElideRight
                            width: Math.min(80, implicitWidth)
                        }
                    }
                }


            }

            // --- Middle Row: Bold Title & Artist + Play/Pause Squircle ---
            Item {
                id: middleRow
                anchors {
                    left: parent.left
                    right: parent.right
                    top: topRow.bottom
                    topMargin: 4
                    leftMargin: 12
                    rightMargin: 12
                }
                height: 46

                // Title and Artist Column
                Column {
                    anchors {
                        left: parent.left
                        right: playSquircle.left
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.trackTitle !== ""
                            ? root.trackTitle
                            : root.trackText
                        font.family: Typography.barFont
                        font.pixelSize: 15
                        font.weight: Typography.weight.bold
                        color: Colors.onSurface
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.trackArtist !== ""
                            ? root.trackArtist
                            : (root.player ? (root.player.identity || "") : "")
                        font.family: Typography.barFont
                        font.pixelSize: 12
                        color: Colors.withAlpha(Colors.onSurface, 0.75)
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }

                // Large Play/Pause Squircle Button
                Rectangle {
                    id: playSquircle

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    width: 42
                    height: 42
                    radius: 14
                    color: root.accentColor
                    scale: playMouseArea.containsMouse ? 1.08 : 1.0

                    Behavior on scale {
                        NumberAnimation { duration: Motion.scale; easing.type: Easing.OutCubic }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: controller.assumedPlaying ? Icons.pause : Icons.playArrow
                        font.family: Typography.iconFont
                        font.pixelSize: 20
                        color: root.accentTextColor
                    }

                    MouseArea {
                        id: playMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: controller.togglePlaying()
                    }
                }
            }

            // --- Bottom Row: Wavy Scrubber (almost full width) & Next Track ---
            Item {
                id: bottomRow
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 12
                    rightMargin: 12
                    bottomMargin: 6
                }
                height: 26

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    WaveformProgress {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        progress: controller.progress
                        position: controller.position
                        length: controller.length
                        playing: controller.assumedPlaying
                        indicatorColor: Colors.onSurface
                        trackColor: Colors.withAlpha(Colors.onSurface, 0.25)
                        onSeekRequested: ratio => controller.seekToPercent(ratio)
                    }

                    IconButton {
                        icon: Icons.skipNext
                        iconSize: Dimensions.icon.large
                        iconColor: Colors.onSurface
                        iconHoverColor: root.accentColor
                        stateColor: root.accentColor
                        opacity: root.player && root.player.canGoNext ? 1.0 : 0.4
                        onClicked: controller.nextTrack()
                    }
                }
            }
        }
    }
}
