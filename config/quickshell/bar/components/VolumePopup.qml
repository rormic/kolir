import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"

// Sound popup for the bar volume pill: output/input volume, mute, device
// selection and Bluetooth codec switching. The content is the same
// SoundControls component the settings popup used to host.
PopupWindow {
    id: root

    property Item anchorItem: null

    // 0 = hidden, 1 = fully visible. Only this surface is animated; the
    // window itself is mapped once at its final size so Wayland never sees
    // a resize during the reveal.
    property real reveal: 0
    property bool pendingReveal: false

    readonly property int panelWidth: 380
    readonly property int panelHeight: 600
    readonly property int headerHeight: 46

    visible: false
    color: "transparent"
    grabFocus: false

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.adjustment: PopupAdjustment.Slide

    implicitWidth: root.panelWidth
    implicitHeight: root.panelHeight

    function open() {
        revealIn.stop();
        revealOut.stop();
        revealFallback.stop();

        if (root.visible && root.reveal > 0.99)
            return;

        root.reveal = 0;
        root.pendingReveal = true;
        root.visible = true;
        grab.active = true;
        controls.refresh();
        revealFallback.restart();
    }

    function close() {
        if (!root.visible)
            return;

        root.pendingReveal = false;
        revealFallback.stop();
        revealIn.stop();
        grab.active = false;

        if (root.reveal <= 0.01) {
            root.visible = false;
            return;
        }

        revealOut.restart();
    }

    function toggle() {
        if (root.visible)
            root.close();
        else
            root.open();
    }

    // Start the reveal on the next event-loop turn, after the popup surface
    // has been mapped. A short timer is used because the first frames of a
    // freshly mapped Wayland popup are not presented.
    function startReveal() {
        if (!root.pendingReveal)
            return;

        root.pendingReveal = false;
        revealFallback.stop();
        revealIn.restart();
    }

    NumberAnimation {
        id: revealIn

        target: root
        property: "reveal"
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: revealOut

        target: root
        property: "reveal"
        to: 0
        duration: 120
        easing.type: Easing.InCubic

        onFinished: {
            if (!root.pendingReveal && root.reveal <= 0.01) {
                root.visible = false;
                root.reveal = 0;
            }
        }
    }

    Timer {
        id: revealFallback

        interval: 40
        repeat: false
        onTriggered: root.startReveal()
    }

    onVisibleChanged: {
        if (!visible) {
            revealFallback.stop();
            revealIn.stop();
            revealOut.stop();
            pendingReveal = false;
            reveal = 0;
            grab.active = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.close()
    }

    IpcHandler {
        target: "volume"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }

    HyprlandFocusGrab {
        id: grab

        windows: [
            root.anchorItem ? root.anchorItem.window : null,
            root
        ]
        onCleared: root.close()
    }

    Item {
        id: panel

        anchors.fill: parent
        opacity: root.reveal
        transform: Translate { y: -(1.0 - root.reveal) * 8 }

        Surface {
            anchors.fill: parent
            radius: Dimensions.radius.extraLarge
            surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
            // Match Hyprland's focused window border.
            borderWidth: 2
            borderColor: Colors.primary
        }

        Item {
            id: content

            anchors.fill: parent

            Item {
                id: header

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: root.headerHeight

                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: 1
                    color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Sound"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.titleSmall
                    font.weight: Typography.weight.bold
                }

                IconButton {
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    icon: Icons.close
                    iconSize: Dimensions.icon.medium
                    onClicked: root.close()
                }
            }

            SoundControls {
                id: controls

                anchors {
                    top: header.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
            }
        }
    }
}
