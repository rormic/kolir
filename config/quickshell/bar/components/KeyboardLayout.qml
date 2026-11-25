import "../../theme"
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Compact keyboard layout label, used inside the clock pill.
//
// The label only exists when the keyboard actually has something to switch
// between: a single-layout setup has no state worth drawing, so the whole
// item (and the Clock's separator before it) disappears. `layoutCount` starts
// at 0 (unknown) and is filled from `hyprctl devices`, which is why a
// multi-layout machine sees the label appear once the first read lands instead
// of a single-layout machine flashing it for a frame.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    visible: layoutCount > 1

    property string layoutName: "EN"
    property int layoutCount: 0

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
                    if (kb && typeof kb.layout === "string") {
                        root.layoutCount = kb.layout
                            .split(",")
                            .filter(part => part.trim().length > 0)
                            .length;
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
