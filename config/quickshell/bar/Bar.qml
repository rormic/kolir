import "../theme"
import "../settings"
import "./components"
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: bar
    WlrLayershell.namespace: "bar"
    WlrLayershell.exclusiveZone: Dimensions.bar.height + Dimensions.bar.margin

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"
    implicitHeight: Dimensions.bar.height + Dimensions.bar.margin

    // The window spans the full top edge so the exclusive zone stays flush,
    // while the visible surface floats inside it with an equal gap on every
    // side. The mask follows the surface so the gaps stay click-through.
    mask: Region {
        x: Dimensions.bar.sideMargin
        y: Dimensions.bar.margin
        width: bar.width - Dimensions.bar.sideMargin * 2
        height: Dimensions.bar.height
        radius: Dimensions.bar.radius
    }

    Rectangle {
        id: background
        anchors {
            top: parent.top
            topMargin: Dimensions.bar.margin
            left: parent.left
            right: parent.right
            leftMargin: Dimensions.bar.sideMargin
            rightMargin: Dimensions.bar.sideMargin
        }
        height: Dimensions.bar.height
        // Very dark, nearly opaque — neon pops on dark
        color: Colors.withAlpha(Colors.surfaceContainerLow, 0.94)
        radius: Dimensions.bar.radius

        // Subtle top highlight
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Dimensions.bar.radius
            anchors.rightMargin: Dimensions.bar.radius
            height: 1
            color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.18)
        }

        // Neon bottom line — the signature accent. Inset by the corner radius
        // so it stays on the flat part of the bottom edge instead of cutting
        // across the rounded corners.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Dimensions.bar.radius
            anchors.rightMargin: Dimensions.bar.radius
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.25; color: Colors.withAlpha(Colors.primary, 0.4) }
                GradientStop { position: 0.5;  color: Colors.withAlpha(Colors.primary, 0.85) }
                GradientStop { position: 0.75; color: Colors.withAlpha(Colors.primary, 0.4) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        // Far left: settings launcher
        SettingsMenu {
            id: settingsMenu
            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent
            anchors.verticalCenter: parent.verticalCenter
        }

        // Left: active window
        ActiveWindow {
            id: activeWindow
            anchors.left: settingsMenu.right
            anchors.leftMargin: Dimensions.spacing.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(190, Math.max(120, background.width * 0.16))
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
            enabled: background.width >= 1100
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
            Brightness      { anchors.verticalCenter: parent.verticalCenter }
            Volume          { anchors.verticalCenter: parent.verticalCenter }
            ThemeToggle     { anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
