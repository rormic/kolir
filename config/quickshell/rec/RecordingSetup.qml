import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../theme"

// Одноразові налаштування запису екрана.
//
// Панель не зберігає вибір нікуди: після Enter значення передаються
// аргументами в screen-record.sh і діють лише на цей запис.
Scope {
    id: root

    // ── Доступні значення ────────────────────────────────────────────────
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

    // ── Поточний вибір (тільки в пам'яті, до першого Enter/Esc) ──────────
    property int fpsIndex: 0
    property int qualityIndex: 1
    property int codecIndex: 0
    property int audioIndex: 0
    property int areaIndex: 0
    property int selectedRow: 0

    function wrapIndex(index, length, direction) {
        return (index + direction + length) % length
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
        // Спочатку ховаємо панель, щоб вона не потрапила у slurp/відео.
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

    // ── Рядок налаштування ───────────────────────────────────────────────
    component OptionRow: Item {
        id: optionRow

        property string title: ""
        property string value: ""
        property bool active: false

        signal previous()
        signal next()
        signal activated()

        width: parent ? parent.width : 0
        height: 36

        Rectangle {
            anchors.fill: parent
            color: optionRow.active ? Colors.primaryContainer : "transparent"
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: optionRow.activated()
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: optionRow.title
            color: optionRow.active ? Colors.onPrimaryContainer : Colors.onSurface
            font.family: Typography.mainFont
            font.pixelSize: 14
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
        }

        PixelBox {
            id: nextButton
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            style: "raised"
            pressed: nextMouse.pressed
            bgColor: Colors.surfaceContainerHigh

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: ">"
                color: Colors.onSurface
                font.family: Typography.mainFont
                font.pixelSize: 14
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
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

        PixelBox {
            id: valueBox
            anchors.right: nextButton.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 190
            height: 22
            style: "sunken"
            bgColor: Colors.surfaceContainerLow

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                width: parent.width - 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: optionRow.value
                color: Colors.onSurface
                font.family: Typography.mainFont
                font.pixelSize: 14
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    optionRow.activated();
                    optionRow.next();
                }
            }
        }

        PixelBox {
            id: prevButton
            anchors.right: valueBox.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            style: "raised"
            pressed: prevMouse.pressed
            bgColor: Colors.surfaceContainerHigh

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: "<"
                color: Colors.onSurface
                font.family: Typography.mainFont
                font.pixelSize: 14
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
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
    }

    // ── Вікно налаштувань ────────────────────────────────────────────────
    PanelWindow {
        id: win

        visible: false
        implicitWidth: 540
        implicitHeight: 284
        color: Colors.surfaceContainer

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "recording-setup"

        onVisibleChanged: if (visible) keyCatcher.forceActiveFocus()

        PixelBox {
            anchors.fill: parent
            style: "raised"
            bgColor: Colors.surfaceContainer

            Item {
                anchors.fill: parent

                // ── Заголовок ──
                Rectangle {
                    id: titleBar
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: 24
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Colors.shadow
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        text: "Recording Setup"
                        color: Colors.primary
                        font.family: Typography.mainFont
                        font.pixelSize: 14
                        font.hintingPreference: Font.PreferFullHinting
                        renderType: Text.NativeRendering
                    }

                    PixelBox {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        style: "raised"
                        pressed: closeMouse.pressed
                        bgColor: closeMouse.containsMouse ? Colors.errorContainer : Colors.surfaceContainerHigh

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: "x"
                            color: closeMouse.containsMouse ? Colors.onErrorContainer : Colors.onSurface
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // ── Футер ──
                Rectangle {
                    id: footer
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: 34
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Colors.shadow
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        text: "[Up/Down] Row  [Left/Right] Change  [Esc] Cancel"
                        color: Colors.outlineVariant
                        font.family: Typography.mainFont
                        font.pixelSize: 12
                        font.hintingPreference: Font.PreferFullHinting
                        renderType: Text.NativeRendering
                    }

                    PixelBox {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 86
                        height: 24
                        style: "raised"
                        pressed: startMouse.pressed
                        bgColor: startMouse.containsMouse ? Colors.primary : Colors.primaryContainer

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: "START"
                            color: startMouse.containsMouse ? Colors.onPrimary : Colors.onPrimaryContainer
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
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

                // ── Список опцій ──
                PixelBox {
                    anchors {
                        top: titleBar.bottom
                        topMargin: 8
                        left: parent.left
                        leftMargin: 8
                        right: parent.right
                        rightMargin: 8
                        bottom: footer.top
                        bottomMargin: 8
                    }
                    style: "sunken"
                    bgColor: Colors.surfaceContainerLowest

                    Column {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 2

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

        // Перехоплювач клавіатури поверх усього вікна.
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
