import QtQuick
import "../../theme"

// One action card in the power sheet. Normal tiles form the 2x2 grid; the
// fullWidth variant is the separate destructive row at the bottom.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property bool destructive: false
    property bool fullWidth: false

    signal activated()

    implicitWidth: 176
    implicitHeight: root.fullWidth ? 52 : 76

    readonly property bool hovered: mouse.containsMouse && root.enabled
    readonly property color accent: root.destructive ? Colors.error : Colors.primary

    opacity: root.enabled ? 1.0 : 0.45
    activeFocusOnTab: root.enabled

    Keys.onReturnPressed: function (event) {
        if (root.enabled)
            root.activated();
        event.accepted = true;
    }

    Keys.onSpacePressed: function (event) {
        if (root.enabled)
            root.activated();
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: Dimensions.radius.large
        color: Colors.surfaceContainerHigh

        StateLayer {
            shown: root.hovered
            tint: root.destructive ? Colors.error : Colors.onSurface
            strength: root.destructive ? 0.10 : 0.14
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Dimensions.radius.large
        color: "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: root.accent
        visible: root.activeFocus
    }

    // Grid tile: icon above the label.
    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: !root.fullWidth

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34
            height: 34
            radius: width / 2
            color: Colors.withAlpha(root.accent, root.hovered ? 0.22 : 0.12)

            Behavior on color {
                ColorAnimation { duration: Motion.hover }
            }

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.accent
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.medium
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.medium
        }
    }

    // Full-width destructive row: icon and label side by side.
    Row {
        anchors.centerIn: parent
        spacing: 9
        visible: root.fullWidth

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: width / 2
            color: Colors.withAlpha(root.accent, root.hovered ? 0.22 : 0.12)

            Behavior on color {
                ColorAnimation { duration: Motion.hover }
            }

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.accent
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.medium
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelLarge
            font.weight: Typography.weight.medium
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled)
                root.activated();
        }
    }
}
