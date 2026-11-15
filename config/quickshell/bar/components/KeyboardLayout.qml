import "../../theme"
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Compact keyboard layout label, used inside the clock pill.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    property string layoutName: "EN"

    Text {
        id: label
        anchors.centerIn: parent
        text: root.layoutName
        color: Colors.onSurfaceVariant
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
        font.weight: Typography.weight.bold
    }

    Process {
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const kb = data.keyboards
                        ? (data.keyboards.find(k => k.main) || data.keyboards[0])
                        : null;
                    if (kb && kb.active_keymap) {
                        const raw = kb.active_keymap.trim();
                        root.layoutName = raw.length > 3
                            ? raw.substring(0, 2).toUpperCase()
                            : raw.toUpperCase();
                    }
                } catch (e) {
                    console.error("KeyboardLayout:", e);
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                const raw = event.data.split(",").slice(1).join(",").trim();
                root.layoutName = raw.length > 3
                    ? raw.substring(0, 2).toUpperCase()
                    : raw.toUpperCase();
            }
        }
    }
}
