import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../theme"

// Індикатор активного запису екрана.
//
// Стан приходить двома шляхами:
//   1) IPC від screen-record.sh — миттєві старт/стоп;
//   2) FileView на recording.json — відновлення після перезапуску Quickshell.
//
// Скрипт заздалегідь вибирає кут екрана, який не перетинається із зоною
// запису, тому індикатор фізично не потрапляє у відео.
Scope {
    id: root

    property bool active: false
    property double startedAt: 0
    property string outputFile: ""
    property int elapsed: 0
    property string corner: "top-right"
    property string monitorName: ""

    readonly property string runtimeDir: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR")
        return dir && dir.length > 0 ? dir : "/tmp"
    }
    readonly property string statePath: runtimeDir + "/kolir/recording.json"

    readonly property bool atTop: corner === "top-right" || corner === "top-left"
    readonly property bool atBottom: corner === "bottom-right" || corner === "bottom-left"
    readonly property bool atLeft: corner === "top-left" || corner === "bottom-left"
    readonly property bool atRight: corner === "top-right" || corner === "bottom-right"

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

        function started(startedSeconds: string, file: string, indicatorCorner: string, monitor: string): void {
            root.active = true
            root.startedAt = Number(startedSeconds) || Math.floor(Date.now() / 1000)
            root.outputFile = file || ""
            root.corner = indicatorCorner || "top-right"
            root.monitorName = monitor || ""
            root.syncElapsed()
        }

        function stopped(file: string): void {
            root.active = false
            root.startedAt = 0
            root.outputFile = ""
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
                    root.outputFile = data.file || ""
                    root.corner = data.corner || "top-right"
                    root.monitorName = data.monitor || ""
                    root.syncElapsed()
                } else {
                    root.active = false
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

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            required property var modelData

            PanelWindow {
                screen: modelData
                visible: root.active && (root.monitorName === "" || modelData.name === root.monitorName)
                color: "transparent"

                anchors.top: root.atTop
                anchors.bottom: root.atBottom
                anchors.left: root.atLeft
                anchors.right: root.atRight

                margins.top: root.atTop ? Dimensions.bar.height + 6 : 0
                margins.bottom: root.atBottom ? 10 : 0
                margins.left: root.atLeft ? 10 : 0
                margins.right: root.atRight ? 10 : 0

                implicitWidth: 160
                implicitHeight: 24

                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "rec-indicator"

                PixelBox {
                    anchors.fill: parent
                    style: "raised"
                    bgColor: Colors.surfaceContainer

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
                                running: true
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
                }
            }
        }
    }
}
