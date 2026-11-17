import "../../theme"
import Quickshell
import Quickshell.Io
import QtQuick

// Recording indicator: pulsing dot + elapsed time. Click stops the recording.
Surface {
    id: root

    property bool active: false
    property double startedAt: 0
    property int elapsed: 0

    readonly property string runtimeDir: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return dir && dir.length > 0 ? dir : "/tmp";
    }
    readonly property string statePath: runtimeDir + "/kolir/recording.json"

    visible: root.active
    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + 16
    radius: Dimensions.radius.full
    surfaceColor: Colors.errorContainer

    function formatTime(sec) {
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const s = sec % 60;
        const mm = m < 10 ? "0" + m : "" + m;
        const ss = s < 10 ? "0" + s : "" + s;
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
    }

    function syncElapsed() {
        root.elapsed = Math.max(0, Math.floor(Date.now() / 1000) - Math.floor(root.startedAt));
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: Colors.onErrorContainer

            SequentialAnimation on opacity {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.25
                    duration: 650
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    to: 1.0
                    duration: 650
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "REC " + root.formatTime(root.elapsed)
            color: Colors.onErrorContainer
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (!stopProc.running)
                stopProc.running = true;
        }
    }

    IpcHandler {
        target: "recording"

        function started(startedSeconds: string, file: string): void {
            root.active = true;
            root.startedAt = Number(startedSeconds) || Math.floor(Date.now() / 1000);
            root.syncElapsed();
        }

        function stopped(file: string): void {
            root.active = false;
            root.startedAt = 0;
            root.elapsed = 0;
        }
    }

    FileView {
        path: root.statePath
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            try {
                const data = JSON.parse(this.text());
                if (data && data.active) {
                    root.active = true;
                    root.startedAt = Number(data.started) || Math.floor(Date.now() / 1000);
                    root.syncElapsed();
                } else {
                    root.active = false;
                    root.elapsed = 0;
                }
            } catch (e) {
                // File does not exist yet: no recording has started.
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

    Process {
        id: stopProc
        command: ["sh", Quickshell.env("HOME") + "/.config/hypr/scripts/screen-record.sh"]
        running: false
    }
}
