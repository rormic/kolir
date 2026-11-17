import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../theme"

// One-shot screen recording options.
//
// The panel does not persist choices: after Enter, values are passed to
// screen-record.sh as arguments and apply only to that recording.
Scope {
    id: root

    // ── Available values ─────────────────────────────────────────────────
    readonly property var fpsKeys: ["auto", "30", "60", "120", "180"]
    readonly property var fpsLabels: ["Auto (native)", "30", "60", "120", "180"]

    readonly property var qualityKeys: ["low", "medium", "high", "max"]
    readonly property var qualityLabels: ["Low (8 Mbps)", "Medium (20 Mbps)", "High (40 Mbps)", "Max (80 Mbps)"]

    readonly property var codecKeys: ["h264", "hevc", "av1"]
    readonly property var codecLabels: ["H.264", "HEVC", "AV1"]

    readonly property var audioKeys: ["system", "mic", "both", "none"]
    readonly property var audioLabels: ["System", "Microphone", "System + Mic", "No audio"]

    readonly property var areaKeys: ["region", "full"]
    readonly property var areaLabels: ["Region", "Full screen"]

    // ── Current selection (in-memory only, until Enter/Esc) ──────────────
    property int fpsIndex: 0
    property int qualityIndex: 1
    property int codecIndex: 0
    property int audioIndex: 0
    property int areaIndex: 0
    property int selectedRow: 0

    function wrapIndex(index, length, direction) {
        return (index + direction + length) % length;
    }

    function cycleFps(direction) {
        root.fpsIndex = root.wrapIndex(root.fpsIndex, root.fpsKeys.length, direction);
    }
    function cycleQuality(direction) {
        root.qualityIndex = root.wrapIndex(root.qualityIndex, root.qualityKeys.length, direction);
    }
    function cycleCodec(direction) {
        root.codecIndex = root.wrapIndex(root.codecIndex, root.codecKeys.length, direction);
    }
    function cycleAudio(direction) {
        root.audioIndex = root.wrapIndex(root.audioIndex, root.audioKeys.length, direction);
    }
    function cycleArea(direction) {
        root.areaIndex = root.wrapIndex(root.areaIndex, root.areaKeys.length, direction);
    }

    function changeSelected(direction) {
        switch (root.selectedRow) {
        case 0:
            root.cycleFps(direction);
            break;
        case 1:
            root.cycleQuality(direction);
            break;
        case 2:
            root.cycleCodec(direction);
            break;
        case 3:
            root.cycleAudio(direction);
            break;
        case 4:
            root.cycleArea(direction);
            break;
        }
    }

    function resetOptions() {
        root.fpsIndex = 0;
        root.qualityIndex = 1;
        root.codecIndex = 0;
        root.audioIndex = 0;
        root.areaIndex = 0;
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
                Quickshell.env("HOME") + "/.config/hypr/scripts/screen-record.sh",
                "--start",
                "--fps", root.fpsKeys[root.fpsIndex],
                "--quality", root.qualityKeys[root.qualityIndex],
                "--codec", root.codecKeys[root.codecIndex],
                "--audio", root.audioKeys[root.audioIndex],
                "--area", root.areaKeys[root.areaIndex]
            ];
            startProc.running = true;
        }
    }

    // ── Option row ───────────────────────────────────────────────────────
    component OptionRow: Item {
        id: optionRow

        property string title: ""
        property string value: ""
        property bool active: false

        signal previous()
        signal next()
        signal activated()

        width: parent ? parent.width : 0
        height: 40

        Rectangle {
            id: rowBg
            anchors.fill: parent
            anchors.margins: 2
            radius: Dimensions.radius.medium
            color: optionRow.active
                ? Colors.withAlpha(Colors.primaryContainer, 0.55)
                : rowMouse.containsMouse
                    ? Colors.stateLayer(Colors.onSurface, 0.06)
                    : "transparent"
            border.width: optionRow.active ? 1 : 0
            border.color: Colors.withAlpha(Colors.primary, 0.35)

            Behavior on color {
                ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            width: 2
            height: 16
            radius: 1
            visible: optionRow.active
            color: Colors.primary
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: optionRow.activated()
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: optionRow.title
            color: optionRow.active ? Colors.onSurface : Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            font.weight: optionRow.active ? Typography.weight.medium : Typography.weight.regular
        }

        Row {
            id: valueControl
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                id: prevButton
                width: 28
                height: 28
                radius: Dimensions.radius.small
                color: prevMouse.containsMouse
                    ? Colors.stateLayer(Colors.onSurface, 0.10)
                    : Colors.withAlpha(Colors.surfaceContainerHigh, 0.9)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: Icons.chevronLeft
                    color: Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: 18
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        optionRow.activated();
                        optionRow.previous();
                    }
                }
            }

            Rectangle {
                id: valueChip
                width: 190
                height: 28
                radius: Dimensions.radius.small
                color: valueMouse.containsMouse
                    ? Colors.withAlpha(Colors.surfaceContainerHighest, 0.95)
                    : Colors.withAlpha(Colors.surfaceContainerHigh, 0.7)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.30)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: optionRow.value
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelLarge
                    font.weight: Typography.weight.medium
                }

                MouseArea {
                    id: valueMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        optionRow.activated();
                        optionRow.next();
                    }
                }
            }

            Rectangle {
                id: nextButton
                width: 28
                height: 28
                radius: Dimensions.radius.small
                color: nextMouse.containsMouse
                    ? Colors.stateLayer(Colors.onSurface, 0.10)
                    : Colors.withAlpha(Colors.surfaceContainerHigh, 0.9)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: Icons.chevronRight
                    color: Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: 18
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        optionRow.activated();
                        optionRow.next();
                    }
                }
            }
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
                Rectangle {
                    id: listCard
                    anchors {
                        top: header.bottom
                        topMargin: 12
                        left: parent.left
                        right: parent.right
                        bottom: footer.top
                        bottomMargin: 12
                    }
                    radius: Dimensions.radius.large
                    color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.55)
                    border.width: 1
                    border.color: Colors.withAlpha(Colors.outlineVariant, 0.20)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        OptionRow {
                            title: "FPS"
                            value: root.fpsLabels[root.fpsIndex]
                            active: root.selectedRow === 0
                            onPrevious: root.cycleFps(-1)
                            onNext: root.cycleFps(1)
                            onActivated: root.selectedRow = 0
                        }

                        OptionRow {
                            title: "Quality"
                            value: root.qualityLabels[root.qualityIndex]
                            active: root.selectedRow === 1
                            onPrevious: root.cycleQuality(-1)
                            onNext: root.cycleQuality(1)
                            onActivated: root.selectedRow = 1
                        }

                        OptionRow {
                            title: "Codec"
                            value: root.codecLabels[root.codecIndex]
                            active: root.selectedRow === 2
                            onPrevious: root.cycleCodec(-1)
                            onNext: root.cycleCodec(1)
                            onActivated: root.selectedRow = 2
                        }

                        OptionRow {
                            title: "Audio"
                            value: root.audioLabels[root.audioIndex]
                            active: root.selectedRow === 3
                            onPrevious: root.cycleAudio(-1)
                            onNext: root.cycleAudio(1)
                            onActivated: root.selectedRow = 3
                        }

                        OptionRow {
                            title: "Area"
                            value: root.areaLabels[root.areaIndex]
                            active: root.selectedRow === 4
                            onPrevious: root.cycleArea(-1)
                            onNext: root.cycleArea(1)
                            onActivated: root.selectedRow = 4
                        }
                    }
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
