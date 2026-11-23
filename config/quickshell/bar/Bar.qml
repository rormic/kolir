import "../theme"
import "../services"
import "../settings"
import "./components"
import Quickshell
import Quickshell.Wayland
import QtQuick

// Caelestia-style docked bar.
//
// The window covers the whole screen on the Top layer but only paints and
// accepts input on the bar strip; the settings popout is drawn below the
// strip in this same surface and expands the mask to the whole screen while
// it is open. The decorative screen frame around the desktop (the window gaps
// and the rounded cut-out) lives in Frame.qml on the Bottom layer, under the
// windows, so it can never clip their borders.
PanelWindow {
    id: bar
    WlrLayershell.namespace: "bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: Dimensions.bar.height

    // The "active window" chip on the left of the strip is disabled for now.
    // The component and its slot stay in the tree so re-enabling is one flag.
    readonly property bool showActiveWindow: false
    // The embedded sheets live in this surface instead of separate windows.
    // OnDemand lets them receive keyboard focus (Escape) after they are
    // clicked without stealing focus while closed.
    WlrLayershell.keyboardFocus: (settingsMenu.opened || brightnessPopup.opened
                                  || volumePopup.opened
                                  || notificationCenter.opened)
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
    }

    // wlr-layer-shell ignores the exclusive zone of a surface anchored to both
    // ends of an axis, so the window is anchored to the top only and sized to
    // the whole screen instead of anchoring bottom too.
    implicitHeight: bar.screen ? bar.screen.height : 0

    color: "transparent"

    // Bar input region: only the bar strip and any active compact notch are
    // interactive; the rest of the surface is click-through.
    readonly property Region barMask: Region {
        Region {
            x: 0
            y: 0
            width: bar.width
            height: Dimensions.bar.height
        }
        Region {
            x: Math.max(0, Math.floor(nowPlaying.x - nowPlaying.notchShoulderRadius))
            y: Dimensions.bar.height
            width: Math.ceil(nowPlaying.notchWidth + nowPlaying.notchShoulderRadius * 2)
            height: nowPlaying.expanded
                ? (nowPlaying.expandedBodyHeight + 30)
                : Math.ceil(nowPlaying.notchDrop)
        }
    }

    // While an embedded sheet is open the whole surface becomes modal, so its
    // full-window dismissal layer can receive outside clicks.
    readonly property Region modalMask: Region {
        x: 0
        y: 0
        width: bar.width
        height: bar.height
    }

    mask: (settingsMenu.modal || brightnessPopup.modal || volumePopup.modal
           || notificationCenter.modal)
        ? modalMask : barMask

    // Bar strip background. The decorative frame below starts at
    // Dimensions.bar.height (see Frame.qml), so the strip is never painted
    // twice, and the fill keeps the bar-blur layer rule working.
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Dimensions.bar.height
        color: Colors.surfaceContainerLow
    }

    // Subtle top highlight
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.18)
    }

    Item {
        id: content

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Math.max(Dimensions.bar.height,
            Dimensions.bar.height + (nowPlaying.expanded ? (nowPlaying.expandedBodyHeight + 40) : Math.ceil(nowPlaying.notchDrop)))
        z: 2

        Item {
            id: barStrip

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Dimensions.bar.height

            // Settings trigger. The panel is drawn by the full-window overlay
            // below, but the button stays in the bar strip above it.
            IconButton {
                id: settingsTrigger

                anchors.left: parent.left
                anchors.leftMargin: Dimensions.padding.barContent
                anchors.verticalCenter: parent.verticalCenter
                icon: Icons.settings
                iconSize: Dimensions.icon.large
                iconOffsetX: -0.5
                iconOffsetY: 1
                active: settingsMenu.opened
                rotation: settingsMenu.opened ? 90 : 0
                onClicked: {
                    brightnessPopup.close();
                    volumePopup.close();
                    settingsMenu.toggle();
                }

                Behavior on rotation {
                    NumberAnimation { duration: Motion.rotate; easing.type: Easing.OutCubic }
                }
            }

            // Left: active window, after the settings button slot. Currently
            // switched off (the chip and its code stay for an easy re-enable);
            // flip `showActiveWindow` to true to bring it back.
            ActiveWindow {
                id: activeWindow
                anchors.left: parent.left
                anchors.leftMargin: Dimensions.padding.barContent + Dimensions.control.iconButton + Dimensions.spacing.small
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(190, Math.max(120, barStrip.width * 0.16))
                visible: bar.showActiveWindow
            }

            // Center: workspaces. No optical offset: the chips on both sides of
            // the pill now share one width, so the pill sits at the screen center.
            Workspaces {
                id: workspaces
                anchors.centerIn: parent
            }

            // Right of center: clock
            Clock {
                id: clock
                anchors.left: workspaces.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
            }

            // Right edge
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Dimensions.padding.barContent
                anchors.verticalCenter: parent.verticalCenter
                spacing: Dimensions.spacing.small

                Tray            { anchors.verticalCenter: parent.verticalCenter }
                RecordingStatus { anchors.verticalCenter: parent.verticalCenter }
                CaffeineIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: {
                        brightnessPopup.close();
                        volumePopup.close();
                        settingsMenu.open("main");
                    }
                }
                DeviceBattery   { anchors.verticalCenter: parent.verticalCenter }
                Battery         { anchors.verticalCenter: parent.verticalCenter }
                Brightness      {
                    id: brightnessChip

                    anchors.verticalCenter: parent.verticalCenter
                    popupActive: brightnessPopup.modal
                    overlayOpen: settingsMenu.modal || volumePopup.modal
                        || notificationCenter.modal
                    onActivated: {
                        settingsMenu.close();
                        volumePopup.close();
                        brightnessPopup.toggle();
                    }
                }
                Volume          {
                    id: volumeChip

                    anchors.verticalCenter: parent.verticalCenter
                    popupActive: volumePopup.modal
                    onActivated: {
                        settingsMenu.close();
                        brightnessPopup.close();
                        volumePopup.toggle();
                    }
                }
                NotificationBell {
                    id: notificationBell

                    anchors.verticalCenter: parent.verticalCenter
                    active: notificationCenter.modal
                    onActivated: {
                        settingsMenu.close();
                        brightnessPopup.close();
                        volumePopup.close();
                        notificationCenter.toggle();
                    }
                }
            }
        }

        // Left of center: now playing. Sits inside content alongside barStrip,
        // anchored to workspaces.left, expanding downward when open.
        NowPlaying {
            id: nowPlaying
            shown: barStrip.width >= 1100
            slotWidth: clock.implicitWidth
            x: workspaces.x - width - 10
            y: 0
            height: Dimensions.bar.height + (expanded ? (expandedBodyHeight + 40) : Math.max(0, notchDrop))
        }
    }

    // Keeps hypridle from locking, blanking or suspending the session while
    // the keep-awake toggle is enabled. Manual lock/suspend still works.
    IdleInhibitor {
        enabled: CaffeineService.enabled
        window: bar
    }

    // Settings panel overlay. It fills the bar window, sits above the strip
    // background but below the bar content, and paints the popout below the
    // bar as a single connected surface.
    SettingsMenu {
        id: settingsMenu
        anchors.fill: parent
        z: 1
    }

    // Night-light sheet overlay. It fills the bar window, sits above the strip
    // background but below the bar content, and mirrors the settings sheet to
    // the right edge as a single connected surface.
    BrightnessPopup {
        id: brightnessPopup
        anchors.fill: parent
        z: 1
    }

    // Sound sheet overlay: same embedded pattern as the night-light sheet.
    VolumePopup {
        id: volumePopup
        anchors.fill: parent
        z: 1
    }

    // Notification center overlay: the bell's history and DND sheet, again
    // embedded in the bar surface and mirrored to the right edge.
    NotificationCenter {
        id: notificationCenter
        anchors.fill: parent
        z: 1
    }

    // The embedded sheets are mutually exclusive, whichever way one was opened
    // (chip click or IPC): opening one closes the others.
    Connections {
        target: brightnessPopup

        function onOpenedChanged() {
            if (brightnessPopup.opened) {
                settingsMenu.close();
                volumePopup.close();
                notificationCenter.close();
                nowPlaying.closeExpanded();
            }
        }
    }

    Connections {
        target: volumePopup

        function onOpenedChanged() {
            if (volumePopup.opened) {
                settingsMenu.close();
                brightnessPopup.close();
                notificationCenter.close();
                nowPlaying.closeExpanded();
            }
        }
    }

    Connections {
        target: settingsMenu

        function onOpenedChanged() {
            if (settingsMenu.opened) {
                brightnessPopup.close();
                volumePopup.close();
                notificationCenter.close();
                nowPlaying.closeExpanded();
            }
        }
    }

    Connections {
        target: notificationCenter

        function onOpenedChanged() {
            if (notificationCenter.opened) {
                settingsMenu.close();
                brightnessPopup.close();
                volumePopup.close();
                nowPlaying.closeExpanded();
            }
        }
    }

    Connections {
        target: nowPlaying

        function onExpandedChanged() {
            if (nowPlaying.expanded) {
                settingsMenu.close();
                brightnessPopup.close();
                volumePopup.close();
                notificationCenter.close();
            }
        }
    }
}
