import "../../theme"
import QtQuick
import QtQuick.Window
import Quickshell.Widgets
import "media"

// Now playing: expanding media island.
//
// At rest it shows the track's cover art (rounded square), the cleaned
// "Artist – Title" line and play/pause, with a thin progress line on the
// pill's bottom edge. On hover the island grows, the text condenses and the
// prev/next buttons slide in around play/pause. A long line is elided with "…"
// and its full text appears in a tooltip under the bar. Clicking the body
// toggles playback; the wheel skips tracks.
//
// While a track is playing with cover art, the island is tinted with Matugen's
// primary_container / on_primary_container from that art. Everything else in
// the shell keeps the system palette. Idle, paused, art-less and failed
// lookups fall back to the regular Colors.
Surface {
    id: root

    MprisController {
        id: controller

        pollActive: root.visible
    }

    // Debounced per-track palette; it only reports colors, the view decides
    // whether they are live.
    CoverPalette {
        id: coverPalette

        artUrl: controller.trackCoverUrl
        active: root.visible && root.assumedPlaying && controller.trackCoverUrl !== ""
    }

    readonly property var player: controller.player

    readonly property bool hasPlayer: controller.hasPlayer
    readonly property bool interactive: controller.interactive
    readonly property bool expanded: hovered && interactive
    readonly property string trackText: controller.trackText
    readonly property string trackCoverUrl: controller.trackCoverUrl

    // Set from Bar.qml: hidden on narrow screens.
    property bool enabled: true
    // Set from Bar.qml to the clock's implicit width. The island keeps at
    // least that width so the workspaces pill stays flanked by two equally
    // wide chips while nothing is playing.
    property int slotWidth: 0

    // No player or no track metadata: show the muted placeholder instead of
    // unmounting the island (which would leave the bar lopsided).
    readonly property bool idle: !hasPlayer || trackText === ""

    visible: enabled

    readonly property bool hovered: _hover.hovered

    readonly property bool progressSupported: controller.progressSupported

    // 0..1 position in the current track. `position` does not update
    // reactively; the controller polls it while playing.
    readonly property real progress: controller.progress

    readonly property bool assumedPlaying: controller.assumedPlaying

    // Cover art wins while it decodes (MPRIS art, else a YouTube thumbnail);
    // AppIcon stays as the fallback, the music note is the last resort. Some
    // players report a bare local path instead of a file:// URL, so normalize
    // it for Image.
    readonly property string artSource: trackCoverUrl === ""
        ? ""
        : (trackCoverUrl.startsWith("/") ? "file://" + trackCoverUrl : trackCoverUrl)
    readonly property bool artReady: artSource !== "" && artImage.status === Image.Ready
    readonly property bool appIconReady: appIcon.ready
    readonly property bool showNoteIcon: !artReady && !appIconReady

    // Palette is live only while the track plays with art. CoverPalette drops
    // paletteReady on pause, stop and helper failure.
    readonly property bool paletteActive: coverPalette.paletteReady

    readonly property color foregroundColor: paletteActive
        ? coverPalette.containerTextColor
        : Colors.onSurface
    // Accent for play/pause, the progress line, the transport icons and the
    // hover border.
    readonly property color accentColor: paletteActive
        ? coverPalette.containerTextColor
        : Colors.primary

    implicitHeight: Dimensions.control.height
    implicitWidth: Math.max(root.slotWidth,
        contentBox.implicitWidth + horizontalPadding * 2)
    radius: Dimensions.radius.full
    surfaceColor: paletteActive
        ? coverPalette.containerColor
        : Colors.surfaceContainerHigh

    // The tooltip is drawn below the pill, so the surface itself must not clip
    // its children. The progress line stays inside the rounded ends.
    clip: false

    readonly property int horizontalPadding: Dimensions.padding.chipHorizontal

    // Neon border on hover; it follows the cover container instead of
    // outlining a tinted pill with a foreign accent.
    borderColor: hovered && interactive
        ? Colors.withAlpha(root.accentColor, 0.55)
        : Colors.withAlpha(paletteActive ? root.foregroundColor : Colors.outlineVariant, 0.18)

    Behavior on borderColor {
        ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
    }

    scale: hovered && interactive ? 1.04 : 1.0

    Behavior on scale {
        NumberAnimation { duration: Motion.scale; easing.type: Easing.OutCubic }
    }

    // Body: click toggles playback, wheel skips tracks. The layout is
    // parented to the MouseArea so wheels over the transport buttons
    // still propagate here, while button clicks stay on the buttons.
    MouseArea {
        id: body

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: controller.togglePlaying()

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                controller.nextTrack();
            else if (wheel.angleDelta.y < 0)
                controller.prevTrack();
        }

        Item {
            id: contentBox

            // Centered so the idle placeholder (a lone note glyph) sits in the
            // middle of the slot instead of hugging its left edge. While a
            // track is present the island is exactly as wide as this item plus
            // the padding, so centering leaves the usual symmetric margins.
            anchors.centerIn: parent
            height: Dimensions.control.height
            implicitWidth: transport.x + transport.width

            // Dim while idle: there is nothing to act on.
            opacity: root.idle ? 0.45 : 1.0

            Behavior on opacity {
                NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
            }

            // Cover art as a rounded square; app icon and note are fallbacks.
            Item {
                id: coverSlot

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Dimensions.media.cover
                height: Dimensions.media.cover

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Dimensions.media.coverRadius
                    color: "transparent"

                    Rectangle {
                        anchors.fill: parent
                        color: Colors.withAlpha(root.accentColor, 0.14)

                        Behavior on color {
                            ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.showNoteIcon
                        text: Icons.musicNote
                        color: root.accentColor
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.small

                        Behavior on color {
                            ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
                        }
                    }

                    // Application icon, used when the track has no cover art.
                    AppIcon {
                        id: appIcon

                        anchors.fill: parent
                        iconSize: coverSlot.width
                        appClass: root.player ? root.player.desktopEntry : ""
                        fallbackIcon: ""
                        visible: !root.artReady && ready
                    }

                    Image {
                        id: artImage

                        anchors.fill: parent
                        source: root.artSource
                        visible: root.artReady
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        sourceSize: Qt.size(
                            Math.ceil(coverSlot.width * Screen.devicePixelRatio),
                            Math.ceil(coverSlot.height * Screen.devicePixelRatio))
                    }
                }
            }

            // Single-line track label, elided with "…"; the full text lives in
            // the tooltip below.
            Text {
                id: trackLabel

                anchors.left: coverSlot.right
                anchors.leftMargin: Dimensions.media.coverSpacing
                anchors.verticalCenter: parent.verticalCenter
                width: root.expanded
                    ? Dimensions.media.textCondensedWidth
                    : Dimensions.media.textMaxWidth
                height: parent.height
                text: root.trackText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foregroundColor
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.bold
                verticalAlignment: Text.AlignVCenter

                Behavior on width {
                    NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
                }

                Behavior on color {
                    ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
                }
            }

            // Transport: prev/next only on hover, play/pause always visible.
            Row {
                id: transport

                anchors.left: trackLabel.right
                anchors.leftMargin: Dimensions.spacing.small
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: Dimensions.media.transportSpacing

                Item {
                    width: root.expanded ? Dimensions.control.iconButton : 0
                    height: Dimensions.control.iconButton
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
                    }

                    IconButton {
                        anchors.centerIn: parent
                        icon: Icons.skipPrevious
                        iconSize: Dimensions.icon.medium
                        iconColor: root.accentColor
                        iconHoverColor: root.accentColor
                        stateColor: root.accentColor
                        opacity: root.player && root.player.canGoPrevious ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: Motion.fade }
                        }

                        onClicked: controller.prevTrack()
                    }
                }

                IconButton {
                    icon: root.assumedPlaying ? Icons.pause : Icons.playArrow
                    iconSize: Dimensions.icon.medium
                    iconColor: root.accentColor
                    iconHoverColor: root.accentColor
                    stateColor: root.accentColor

                    onClicked: controller.togglePlaying()
                }

                Item {
                    width: root.expanded ? Dimensions.control.iconButton : 0
                    height: Dimensions.control.iconButton
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
                    }

                    IconButton {
                        anchors.centerIn: parent
                        icon: Icons.skipNext
                        iconSize: Dimensions.icon.medium
                        iconColor: root.accentColor
                        iconHoverColor: root.accentColor
                        stateColor: root.accentColor
                        opacity: root.player && root.player.canGoNext ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: Motion.fade }
                        }

                        onClicked: controller.nextTrack()
                    }
                }
            }
        }
    }

    // Full track line under the bar while the label is elided.
    Rectangle {
        id: tooltip

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + Dimensions.spacing.small
        z: 10
        width: tooltipLabel.implicitWidth + Dimensions.padding.chipHorizontal * 2
        height: tooltipLabel.implicitHeight + Dimensions.spacing.small * 2
        radius: Dimensions.radius.small
        color: Colors.surfaceContainerHighest
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)
        visible: root.hovered && root.trackText !== "" && trackLabel.truncated

        Behavior on color {
            ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
        }

        Text {
            id: tooltipLabel

            anchors.centerIn: parent
            text: root.trackText
            textFormat: Text.PlainText
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.regular
        }
    }

    // Thin progress line on the bottom edge of the pill, in the style of the
    // Volume chip.
    Rectangle {
        x: Dimensions.media.progressInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dimensions.media.progressBottomMargin
        width: (parent.width - Dimensions.media.progressInset * 2) * root.progress
        height: Dimensions.media.progressThickness
        radius: Dimensions.media.progressThickness / 2
        visible: root.progressSupported
        color: root.assumedPlaying
            ? Colors.withAlpha(root.accentColor, 0.75)
            : Colors.withAlpha(root.accentColor, 0.3)

        Behavior on width {
            NumberAnimation { duration: Motion.mediaProgress; easing.type: Easing.OutCubic }
        }

        Behavior on color {
            ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
        }
    }

    HoverHandler { id: _hover }
}
