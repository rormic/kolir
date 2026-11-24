import "../../services"
import "../../theme"
import Quickshell.Io
import QtQuick

// Recording status: a flat red alert, not a menu chip.
//
// The pulsing dot and elapsed time are information; clicking the alert stops
// the recording, which is the action the alert itself implies. Keeping it flat
// stops it from competing with the brightness/volume pills next to it.
StatusItem {
    id: root

    property bool active: false
    property double startedAt: 0
    property int elapsed: 0

    visible: root.active
    icon: Icons.record
    iconSize: 10
    iconColor: Colors.error
    text: "REC " + root.formatTime(root.elapsed)
    textWeight: Typography.weight.bold
    textColor: Colors.error
    spacing: 5

    // Leave the dot at full opacity for the next recording instead of keeping
    // whatever dim phase the pulse stopped on.
    onActiveChanged: if (!active) iconItem.opacity = 1

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

    // The dot breathes while a recording is running. The item is hidden when
    // it is not, so the animation costs nothing at rest.
    SequentialAnimation {
        running: root.active
        loops: Animation.Infinite

        NumberAnimation {
            target: root.iconItem
            property: "opacity"
            to: 0.25
            duration: 650
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root.iconItem
            property: "opacity"
            to: 1.0
            duration: 650
            easing.type: Easing.InOutQuad
        }
    }

    MouseArea {
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
        path: ShellPaths.recordingState
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
        command: ["sh", ShellPaths.hyprScripts + "/screen-record.sh"]
        running: false
    }
}
