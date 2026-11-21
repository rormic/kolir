import QtQuick
import Quickshell
import Quickshell.Wayland
import "../bar/components"
import "../theme"

// Shared bottom-center OSD surface: reveal/hide lifecycle, pill chrome and
// the icon / progress / value row. Domain services stay in the wrappers.
PanelWindow {
    id: root

    property string layerNamespace: "osd"

    property string icon: ""
    property color iconColor: Colors.primary
    property real value: 0
    property color indicatorColor: Colors.primary
    property color borderColor: Colors.withAlpha(Colors.primary, 0.45)
    property color glowColor: Colors.withAlpha(Colors.primary, 0.7)
    property string text: ""
    property color textColor: Colors.onSurface

    // True while the panel is revealed; drives the fade and keeps the surface
    // alive until the hide animation finishes.
    property bool shown: false

    function show() {
        visible = true;
        shown = true;
        hideTimer.restart();
    }

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
    WlrLayershell.namespace: root.layerNamespace

    Timer {
        id: hideTimer
        interval: 1500
        repeat: false
        onTriggered: root.shown = false
    }

    Item {
        id: container
        anchors.fill: parent

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : 0.94
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!running && !root.shown) {
                        root.visible = false;
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
            border.color: root.borderColor

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
                        color: root.glowColor
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

                // Mode icon
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    font.family: Typography.iconFont
                    font.pixelSize: 18
                    color: root.iconColor
                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                // Material 3 linear progress indicator: wavy while the OSD
                // is visible, flat track with a gap and a stop dot.
                ProgressIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 18 - 8 - 36 - 8 // width minus icon, gaps, text
                    height: implicitHeight
                    value: root.value
                    indicatorColor: root.indicatorColor
                    trackColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)
                    wavy: true
                    playing: root.shown
                }

                // Value text
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    text: root.text
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                    color: root.textColor
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }
    }
}
