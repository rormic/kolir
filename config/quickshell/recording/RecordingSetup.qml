import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../services"
import "../theme"

// One-shot screen recording options.
//
// The panel does not persist choices: after Enter, values are passed to
// screen-record.sh as arguments and apply only to that recording.
Scope {
    id: root

    // ── Available values ─────────────────────────────────────────────────
    readonly property var options: [
        {
            title: "FPS",
            keys: ["auto", "30", "60", "120", "180"],
            labels: ["Auto (native)", "30", "60", "120", "180"],
        },
        {
            title: "Quality",
            keys: ["low", "medium", "high", "max"],
            labels: ["Low (8 Mbps)", "Medium (20 Mbps)", "High (40 Mbps)", "Max (80 Mbps)"],
        },
        {
            title: "Codec",
            keys: ["h264", "hevc", "av1"],
            labels: ["H.264", "HEVC", "AV1"],
        },
        {
            title: "Audio",
            keys: ["system", "mic", "both", "none"],
            labels: ["System", "Microphone", "System + Mic", "No audio"],
        },
        {
            title: "Area",
            keys: ["region", "full"],
            labels: ["Region", "Full screen"],
        },
    ]

    // ── Current selection (in-memory only, until Enter/Esc) ──────────────
    property var optionIndexes: [0, 1, 0, 0, 0]
    property int selectedRow: 0

    function wrapIndex(index, length, direction) {
        return (index + direction + length) % length;
    }

    function cycleOption(row, direction) {
        const next = root.optionIndexes.slice();
        next[row] = root.wrapIndex(next[row], root.options[row].keys.length, direction);
        root.optionIndexes = next;
    }

    function optionKey(row) {
        return root.options[row].keys[root.optionIndexes[row]];
    }

    function changeSelected(direction) {
        root.cycleOption(root.selectedRow, direction);
    }

    function resetOptions() {
        root.optionIndexes = [0, 1, 0, 0, 0];
        root.selectedRow = 0;
    }

    function open() {
        root.resetOptions();
        win.visible = true;
        keyCatcher.forceActiveFocus();
    }

    function close() {
        win.visible = false;
    }

    function startRecording() {
        // Hide the panel first so it does not appear in slurp/video.
        win.visible = false;
        launchTimer.restart();
    }

    IpcHandler {
        target: "recordingSetup"

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }

    Process {
        id: startProc
        running: false
    }

    Timer {
        id: launchTimer
        interval: 150
        repeat: false

        onTriggered: {
            startProc.command = [
                "sh",
                ShellPaths.hyprScripts + "/screen-record.sh",
                "--start",
                "--fps", root.optionKey(0),
                "--quality", root.optionKey(1),
                "--codec", root.optionKey(2),
                "--audio", root.optionKey(3),
                "--area", root.optionKey(4)
            ];
            startProc.running = true;
        }
    }

    // ── Settings window ──────────────────────────────────────────────────
    PanelWindow {
        id: win

        visible: false
        implicitWidth: 520
        implicitHeight: 360
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "recording-setup"

        onVisibleChanged: if (visible) keyCatcher.forceActiveFocus()

        Surface {
            id: panel
            anchors.fill: parent
            radius: Dimensions.radius.extraLarge
            surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
            borderWidth: 2
            borderColor: Colors.primary

            Item {
                anchors.fill: parent
                anchors.margins: 16

                // ── Header ──
                Item {
                    id: header
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.record
                        color: Colors.primary
                        font.family: Typography.iconFont
                        font.pixelSize: 20
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Recording Setup"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.titleSmall
                        font.weight: Typography.weight.bold
                    }
                }

                // ── Footer ──
                Item {
                    id: footer
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: 36

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.35)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "[Up/Down] Row  [Left/Right] Change  [Esc] Cancel"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                    }

                    Rectangle {
                        id: startButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        height: 30
                        radius: Dimensions.radius.medium
                        color: startMouse.containsMouse
                            ? Colors.primary
                            : Colors.primaryContainer
                        border.width: 1
                        border.color: Colors.withAlpha(Colors.primary, 0.35)

                        Behavior on color {
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.record
                                color: startMouse.containsMouse ? Colors.onPrimary : Colors.onPrimaryContainer
                                font.family: Typography.iconFont
                                font.pixelSize: 16
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "START"
                                color: startMouse.containsMouse ? Colors.onPrimary : Colors.onPrimaryContainer
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelLarge
                                font.weight: Typography.weight.bold
                            }
                        }

                        MouseArea {
                            id: startMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startRecording()
                        }
                    }
                }

                // ── Options list ──
                RecordingOptions {
                    anchors {
                        top: header.bottom
                        topMargin: 12
                        left: parent.left
                        right: parent.right
                        bottom: footer.top
                        bottomMargin: 12
                    }
                    options: root.options
                    indexes: root.optionIndexes
                    selectedRow: root.selectedRow
                    onCycled: (row, direction) => root.cycleOption(row, direction)
                    onActivated: row => root.selectedRow = row
                }
            }
        }

        // Keyboard focus catcher over the whole window.
        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Up) {
                    root.selectedRow = (root.selectedRow + 4) % 5;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.selectedRow = (root.selectedRow + 1) % 5;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root.changeSelected(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.changeSelected(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.startRecording();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }
}
