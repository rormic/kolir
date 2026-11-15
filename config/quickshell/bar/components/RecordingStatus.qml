import "../../theme"
import Quickshell
import Quickshell.Io
import QtQuick

// RecordingStatus — індикатор активного запису екрана в статусбарі.
//
// Стан приходить двома шляхами:
//   1) IPC від screen-record.sh — миттєві старт/стоп;
//   2) FileView на recording.json — відновлення після перезапуску Quickshell.
// Клік по індикатору зупиняє запис.
PixelBox {
    id: root

    property bool active: false
    property double startedAt: 0
    property int elapsed: 0

    readonly property string runtimeDir: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR")
        return dir && dir.length > 0 ? dir : "/tmp"
    }
    readonly property string statePath: runtimeDir + "/kolir/recording.json"

    visible: root.active

    style: "raised"
    pressed: mouse.pressed
    bgColor: mouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh

    implicitWidth: 108
    implicitHeight: Dimensions.bar.height - 4

    function formatTime(sec) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        const s = sec % 60
        const mm = m < 10 ? "0" + m : "" + m
        const ss = s < 10 ? "0" + s : "" + s
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
    }

    function syncElapsed() {
        root.elapsed = Math.max(0, Math.floor(Date.now() / 1000) - Math.floor(root.startedAt))
    }

    IpcHandler {
        target: "recording"

        function started(startedSeconds: string, file: string): void {
            root.active = true
            root.startedAt = Number(startedSeconds) || Math.floor(Date.now() / 1000)
            root.syncElapsed()
        }

        function stopped(file: string): void {
            root.active = false
            root.startedAt = 0
            root.elapsed = 0
        }
    }

    FileView {
        path: root.statePath
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            try {
                const data = JSON.parse(this.text())
                if (data && data.active) {
                    root.active = true
                    root.startedAt = Number(data.started) || Math.floor(Date.now() / 1000)
                    root.syncElapsed()
                } else {
                    root.active = false
                    root.elapsed = 0
                }
            } catch (e) {
                // Файлу ще немає — запис не починався.
            }
        }
    }

    Timer {
        running: root.active
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.syncElapsed()
    }

    Row {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        spacing: 6

        Rectangle {
            width: 8
            height: 8
            color: Colors.error
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation on opacity {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.2
                    duration: 500
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    to: 1.0
                    duration: 500
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Text {
            text: "REC " + root.formatTime(root.elapsed)
            color: Colors.onSurface
            font.family: Typography.mainFont
            font.pixelSize: 14
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (!stopProc.running)
                stopProc.running = true
        }
    }

    Process {
        id: stopProc
        command: ["sh", Quickshell.env("HOME") + "/.config/hypr/scripts/screen-record.sh"]
        running: false
    }
}
