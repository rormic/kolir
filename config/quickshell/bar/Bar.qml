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
    // The settings popout lives in this surface instead of a separate window.
    // OnDemand lets the menu receive keyboard focus (Escape, Wi-Fi password)
    // after it is clicked without stealing focus when it is closed.
    WlrLayershell.keyboardFocus: settingsMenu.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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

    // Bar input region: only the bar strip is interactive, the rest of the
    // surface is click-through. The decorative screen frame is a separate
    // Bottom-layer surface (Frame.qml) with an empty mask of its own.
    readonly property Region barMask: Region {
        x: 0
        y: 0
        width: bar.width
        height: Dimensions.bar.height
    }

    // While the settings popout is open the whole surface becomes modal, so
    // the full-window dismissal layer can receive outside clicks.
    readonly property Region modalMask: Region {
        x: 0
        y: 0
        width: bar.width
        height: bar.height
    }

    mask: settingsMenu.modal ? modalMask : barMask

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
        height: Dimensions.bar.height
        z: 2

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
            onClicked: settingsMenu.toggle()

            Behavior on rotation {
                NumberAnimation { duration: Motion.rotate; easing.type: Easing.OutCubic }
            }
        }

        // Left: active window, after the settings button slot.
        ActiveWindow {
            id: activeWindow
            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent + Dimensions.control.iconButton + Dimensions.spacing.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(190, Math.max(120, content.width * 0.16))
        }

        // Center: workspaces
        Workspaces {
            id: workspaces
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: workspaces.cellWidth / 2
        }

        // Left of center: now playing
        NowPlaying {
            id: nowPlaying
            enabled: content.width >= 1100
            anchors.right: workspaces.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
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
                onActivated: settingsMenu.open("main")
            }
            Brightness      { anchors.verticalCenter: parent.verticalCenter }
            Volume          { anchors.verticalCenter: parent.verticalCenter }
            ThemeToggle     { anchors.verticalCenter: parent.verticalCenter }
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
}
