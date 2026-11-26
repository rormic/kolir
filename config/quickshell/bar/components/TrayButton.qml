import QtQuick
import Quickshell.Services.SystemTray
import "../../theme"

// Compact status notifier icon. Left click opens the item's menu when it has
// one and otherwise activates it, middle click calls secondaryActivate and the
// wheel is forwarded to the application (volume mixers, etc.). Right click is
// deliberately unhandled.
Item {
    id: root

    required property var trayItem
    property bool menuOpen: false

    signal menuRequested(var item, var anchor)

    readonly property bool hovered: mouse.containsMouse
    readonly property bool needsAttention: root.trayItem
        && root.trayItem.status === Status.NeedsAttention
    readonly property string iconSource: root.trayItem ? root.trayItem.icon : ""

    implicitWidth: Dimensions.control.iconButton
    implicitHeight: Dimensions.bar.height

    scale: mouse.pressed ? 0.9 : root.hovered ? 1.06 : 1.0
    // Small interactive control scale: the M3 fast spatial spring.
    Behavior on scale {
        SpringAnimation {
            spring: Motion.spatialSpringFast
            damping: Motion.spatialSpringFastDamping
            epsilon: Motion.springScaleEpsilon
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Dimensions.control.iconButton
        height: Dimensions.control.iconButton
        radius: width / 2

        color: root.menuOpen
            ? Colors.stateLayer(Colors.primary, 0.15)
            : mouse.pressed
                ? Colors.stateLayer(Colors.onSurface, 0.14)
                : root.hovered
                    ? Colors.stateLayer(Colors.onSurface, 0.07)
                    : "transparent"

        border.width: root.hovered || root.menuOpen ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.6)

        Behavior on color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    Image {
        id: trayIcon

        anchors.centerIn: parent
        width: Dimensions.icon.large
        height: Dimensions.icon.large
        source: root.iconSource
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: source !== "" && status === Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: !trayIcon.visible
        text: Icons.apps
        color: root.hovered ? Colors.primary : Colors.onSurfaceVariant
        font.family: Typography.iconFont
        font.pixelSize: Dimensions.icon.large
        Behavior on color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    // "Needs attention" dot, used by chat and mail clients.
    Rectangle {
        visible: root.needsAttention
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 2
        anchors.rightMargin: 1
        width: 5
        height: 5
        radius: 2.5
        color: Colors.error
        border.width: 1
        border.color: Colors.surfaceContainerLow
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor

        onClicked: event => {
            if (event.button === Qt.LeftButton) {
                if (root.trayItem.hasMenu)
                    root.menuRequested(root.trayItem, root);
                else
                    root.trayItem.activate();
            } else if (event.button === Qt.MiddleButton) {
                root.trayItem.secondaryActivate();
            }
        }

        onWheel: wheel => {
            const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
            const delta = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y;
            if (delta !== 0)
                root.trayItem.scroll(delta, horizontal);
        }
    }
}
