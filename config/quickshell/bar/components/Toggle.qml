import QtQuick
import "../../theme"

// Neon Material toggle. Controlled: the parent owns `checked`, this only
// reports taps via `toggled` so bindings never fight each other.
Item {
    id: root

    property bool checked: false
    property bool interactive: true

    signal toggled(bool checked)

    implicitWidth: 36
    implicitHeight: 20

    opacity: root.interactive ? 1.0 : 0.4

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: root.checked
            ? Colors.withAlpha(Colors.primary, 0.5)
            : Colors.surfaceContainerHighest
        border.width: 1
        border.color: root.checked
            ? Colors.withAlpha(Colors.primary, 0.8)
            : Colors.withAlpha(Colors.outlineVariant, 0.35)

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    Rectangle {
        id: knob

        y: 2
        width: 16
        height: 16
        radius: 8
        x: root.checked ? root.width - width - 2 : 2
        color: root.checked ? Colors.primary : Colors.onSurfaceVariant

        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
