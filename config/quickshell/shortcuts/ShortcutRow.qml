import QtQuick
import "../theme"

// One row of the shortcuts overlay: the key or gesture chip in a fixed column
// and the action description. The modifier set is named once by the section
// header above, so rows stay narrow enough for long descriptions.
Item {
    id: root

    property string keyLabel: ""
    property string description: ""

    readonly property int keyColumnWidth: 132
    readonly property int chipHeight: 24

    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Dimensions.radius.small
        color: rowMouse.containsMouse
            ? Colors.stateLayer(Colors.onSurface, 0.06)
            : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    KeyChip {
        anchors {
            left: parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        height: root.chipHeight
        maxWidth: root.keyColumnWidth - 12
        label: root.keyLabel
    }

    Text {
        anchors {
            left: parent.left
            leftMargin: root.keyColumnWidth
            right: parent.right
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: root.description
        color: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.bodyMedium
        font.weight: Typography.weight.regular
        elide: Text.ElideRight
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
    }
}
