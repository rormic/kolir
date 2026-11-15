import "../theme"
import "./components"
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: bar
    WlrLayershell.namespace: "bar"
    WlrLayershell.exclusiveZone: Dimensions.bar.height

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"
    implicitHeight: Dimensions.bar.height

    Rectangle {
        id: background
        anchors.fill: parent
        color: Colors.withAlpha(Colors.surfaceContainer, 0.86)

        // Left: active window
        ActiveWindow {
            id: activeWindow
            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(190, Math.max(120, background.width * 0.16))
        }

        // Center: workspaces. The row holds ten cells, so shift the whole
        // cluster half a cell to the right to put workspace 5 exactly in the
        // middle of the screen.
        Workspaces {
            id: workspaces
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: workspaces.cellWidth / 2
        }

        // Left of center: now playing, like main
        NowPlaying {
            id: nowPlaying
            enabled: background.width >= 1100
            anchors.right: workspaces.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        // Right of center: clock + language, like main
        Clock {
            id: clock
            anchors.left: workspaces.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        // Right edge: recording, volume, theme
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Dimensions.spacing.small

            RecordingStatus {
                anchors.verticalCenter: parent.verticalCenter
            }

            Brightness {
                anchors.verticalCenter: parent.verticalCenter
            }

            Volume {
                anchors.verticalCenter: parent.verticalCenter
            }

            ThemeToggle {
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
