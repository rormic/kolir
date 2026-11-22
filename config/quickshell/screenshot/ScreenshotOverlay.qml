pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Frozen-frame screenshot overlay. SUPER+X captures the focused monitor to a
// PNG, this surface shows that still image full-screen, and slurp draws the
// selection rectangle on top of it. Selecting over a frozen frame means the
// content behind the choice cannot move, which is the whole point of the
// feature.
//
// The surface lives on the Top layer (below slurp's Overlay layer), is
// click-through (empty mask) and does not take keyboard focus, so the pointer
// and Escape both reach slurp. The shell script owns the capture, the slurp
// invocation and the final crop.
Scope {
    id: root

    property string imagePath: ""

    function open(path) {
        root.imagePath = path;
        if (!win.visible)
            win.visible = true;
    }

    function close() {
        win.visible = false;
    }

    function toggle() {
        if (win.visible) {
            root.close();
        } else if (root.imagePath !== "") {
            root.open(root.imagePath);
        }
    }

    IpcHandler {
        target: "screenshot"

        function open(path: string): void {
            root.open(path);
        }

        function close(): void {
            root.close();
        }

        function toggle(): void {
            root.toggle();
        }
    }

    PanelWindow {
        id: win

        visible: false
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        // slurp owns the keyboard (Escape) and is composited above this surface
        // on the Overlay layer; the empty mask keeps the frozen image
        // click-through so the pointer reaches slurp as well.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "screenshot"
        mask: Region {}

        onVisibleChanged: {
            if (!visible)
                root.imagePath = "";
        }

        Image {
            anchors.fill: parent
            source: root.imagePath !== "" ? "file://" + root.imagePath : ""
            fillMode: Image.Stretch
            // Синхронне декодування: зображення готове до того, як поверхню
            // відображено, тож скрипт не чекає на асинхронний завантаження.
            asynchronous: false
            cache: false
        }
    }
}
