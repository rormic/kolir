import "../../theme"
import QtQuick
import "media"

// Now playing: expanding media island.
//
// Collapsed it is an info chip: site/app icon, "Artist – Title", and a
// thin neon progress line at the bottom (the "playing" indicator — it
// moves while playing, dims and freezes on pause). On hover the island
// grows, the text condenses and transport buttons (prev / play-pause /
// next) slide in. Clicking the body toggles playback; the wheel skips
// tracks.
Surface {
    id: root

    MprisController {
        id: controller

        pollActive: root.visible
    }

    readonly property var player: controller.player

    readonly property bool hasPlayer: controller.hasPlayer
    readonly property bool interactive: controller.interactive
    readonly property bool expanded: hovered && interactive
    readonly property string trackText: controller.trackText

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

    // Collapsed vs hovered text viewport widths. The island grows by
    // roughly the amount the text condenses, so it barely shifts when the
    // buttons slide in.
    readonly property int textMaxWidth: 150
    readonly property int textCondensedWidth: 110
    readonly property int horizontalPadding: Dimensions.padding.chipHorizontal

    readonly property bool progressSupported: controller.progressSupported

    // 0..1 position in the current track. `position` does not update
    // reactively; the controller polls it while playing.
    readonly property real progress: controller.progress

    readonly property bool siteIconReady: controller.siteIconPath !== ""
        && siteIconImage.status === Image.Ready

    // AppIcon resolves the player's desktop entry (zen -> zen-browser, ...).
    readonly property bool appIconReady: appIcon.ready

    // The music note is the last resort, used only when no icon is available.
    readonly property bool showNoteIcon: !siteIconReady && !appIconReady

    readonly property bool assumedPlaying: controller.assumedPlaying

    implicitHeight: Dimensions.control.height
    implicitWidth: Math.max(root.slotWidth,
        content.implicitWidth + horizontalPadding * 2)
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // Neon border on hover
    borderColor: hovered && interactive
        ? Colors.withAlpha(Colors.primary, 0.55)
        : Colors.withAlpha(Colors.outlineVariant, 0.18)

    Behavior on borderColor {
        ColorAnimation { duration: 150 }
    }

    scale: hovered && interactive ? 1.04 : 1.0

    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    onExpandedChanged: viewport.syncMarquee()

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
            id: content

            // Centered so the idle placeholder (a lone note glyph) sits in the
            // middle of the slot instead of hugging its left edge. While a
            // track is present the island is exactly as wide as this item plus
            // the padding, so centering leaves the usual symmetric margins.
            anchors.centerIn: parent
            height: Dimensions.control.height
            implicitWidth: controlsSlot.x + controlsSlot.width

            // Dim while paused, unless hovered for interacting. The idle
            // placeholder stays muted even on hover: there is nothing to act on.
            opacity: root.idle
                ? 0.45
                : (root.assumedPlaying
                    ? 1.0
                    : (root.hovered && root.interactive ? 1.0 : 0.6))

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
                    visible: root.showNoteIcon
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.showNoteIcon
                    text: Icons.musicNote
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: 12
                }

                // Application icon, used when the site has no favicon.
                AppIcon {
                    id: appIcon

                    anchors.fill: parent
                    iconSize: coverSlot.width
                    appClass: root.player ? root.player.desktopEntry : ""
                    fallbackIcon: ""
                    visible: !root.siteIconReady && ready
                }

                // Site favicon extracted from the browser's local cache.
                Image {
                    id: siteIconImage

                    anchors.fill: parent
                    visible: controller.siteIconPath !== ""
                    opacity: root.siteIconReady ? 1 : 0
                    source: controller.siteIconPath !== ""
                        ? "file://" + controller.siteIconPath
                        : ""
                    sourceSize: Qt.size(coverSlot.width, coverSlot.height)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true

                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    onStatusChanged: {
                        if (status === Image.Error)
                            controller.clearSiteIcon();
                    }
                }
            }

            // Clipped text viewport; marquee for overflowing titles.
            MarqueeText {
                id: viewport

                anchors.left: coverSlot.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: Math.min(viewport.textWidth,
                    root.expanded ? root.textCondensedWidth : root.textMaxWidth)
                text: root.trackText

                Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
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
                        opacity: root.player && root.player.canGoPrevious ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        onClicked: controller.prevTrack()
                    }

                    IconButton {
                        icon: root.assumedPlaying ? Icons.pause : Icons.playArrow
                        iconSize: Dimensions.icon.medium
                        iconColor: Colors.primary

                        onClicked: controller.togglePlaying()
                    }

                    IconButton {
                        icon: Icons.skipNext
                        iconSize: Dimensions.icon.medium
                        iconColor: Colors.onSurfaceVariant
                        opacity: root.player && root.player.canGoNext ? 1 : 0.35

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        onClicked: controller.nextTrack()
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

    HoverHandler { id: _hover }
}
