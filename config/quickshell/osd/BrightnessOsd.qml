import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"

Scope {
    id: root

    property bool active: false

    Timer {
        id: hideTimer
        interval: 1500
        repeat: false
        onTriggered: root.active = false
    }

    Connections {
        target: BrightnessService
        function onBrightnessChangedManually(val) {
            osdWin.visible = true
            root.active = true
            hideTimer.restart()
        }
    }

    PanelWindow {
        id: osdWin

        visible: false
        color: "transparent"

        anchors {
            bottom: true
        }
        margins.bottom: 60

        implicitWidth: 200
        implicitHeight: 36

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "brightness-osd"

        Item {
            id: container
            anchors.fill: parent

            opacity: root.active ? 1.0 : 0.0
            scale: root.active ? 1.0 : 0.94
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                    onRunningChanged: {
                        if (!running && !root.active) {
                            osdWin.visible = false
                        }
                    }
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            // ── Compact Neon Pill ──
            Rectangle {
                anchors.fill: parent
                radius: parent.height / 2
                color: Colors.withAlpha(Colors.surfaceContainerLow, 0.94)

                border.width: 1
                border.color: Colors.withAlpha(Colors.primary, 0.45)

                Behavior on border.color {
                    ColorAnimation { duration: 140 }
                }

                // Subtle neon bottom highlight
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.6
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop {
                            position: 0.5
                            color: Colors.withAlpha(Colors.primary, 0.7)
                        }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Row {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 8

                    // Brightness Icon
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: BrightnessService.value < 34
                            ? Icons.brightnessLow
                            : (BrightnessService.value < 67
                                ? Icons.brightnessMedium
                                : Icons.brightnessHigh)
                        font.family: Typography.iconFont
                        font.pixelSize: 18
                        color: Colors.primary
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    // Progress Slider
                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 18 - 8 - 36 - 8 // width minus icon, gaps, text
                        height: 4
                        radius: 2
                        color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)

                        Rectangle {
                            id: fill
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(0, Math.min(track.width, track.width * (Math.min(100, Math.max(0, BrightnessService.value)) / 100)))
                            radius: 2
                            color: Colors.primary

                            Behavior on width {
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }
                        }
                    }

                    // Value text
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        horizontalAlignment: Text.AlignRight
                        text: BrightnessService.value + "%"
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.bold
                        color: Colors.onSurface
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }
            }
        }
    }
}
