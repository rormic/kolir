import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../bar/components"
import "../theme"

// Shared anchored popup mechanics for the bar popouts: mapping, reveal and
// dismissal animation, focus grab, Escape to close and the Surface chrome.
// Domain-specific refresh, IPC targets and headers stay in the wrappers.
PopupWindow {
    id: root

    property Item anchorItem: null

    // 0 = hidden, 1 = fully visible. Only this surface is animated; the
    // window itself is mapped once at its final size so Wayland never sees
    // a resize during the reveal.
    property real reveal: 0
    property bool pendingReveal: false

    property int panelWidth: 380
    property int panelHeight: 600
    property int headerHeight: 46

    property alias headerContent: headerSlot.data
    default property alias content: contentSlot.data

    // Emitted after the surface is mapped and grab is taken, before the
    // reveal animation starts.
    signal opened()
    // Emitted once the surface has fully hidden and its animation state reset.
    signal hidden()

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
        root.opened();
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
        duration: Motion.popupEnter
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: revealOut

        target: root
        property: "reveal"
        to: 0
        duration: Motion.popupExit
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
            root.hidden();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.close()
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
            id: headerSlot

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
        }

        Item {
            id: contentSlot

            anchors {
                top: headerSlot.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
        }
    }
}
