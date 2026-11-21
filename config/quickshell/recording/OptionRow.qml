import QtQuick
import "../theme"

// One selectable recording option: row highlight, title and the
// previous / value / next control on the right.
Item {
    id: optionRow

    property string title: ""
    property string value: ""
    property bool active: false

    signal previous()
    signal next()
    signal activated()

    width: parent ? parent.width : 0
    height: 40

    Rectangle {
        id: rowBg
        anchors.fill: parent
        anchors.margins: 2
        radius: Dimensions.radius.medium
        color: optionRow.active
            ? Colors.withAlpha(Colors.primaryContainer, 0.55)
            : rowMouse.containsMouse
                ? Colors.stateLayer(Colors.onSurface, 0.06)
                : "transparent"
        border.width: optionRow.active ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.35)

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width: 2
        height: 16
        radius: 1
        visible: optionRow.active
        color: Colors.primary
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: optionRow.activated()
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: optionRow.title
        color: optionRow.active ? Colors.onSurface : Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.bodyMedium
        font.weight: optionRow.active ? Typography.weight.medium : Typography.weight.regular
    }

    Row {
        id: valueControl
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Rectangle {
            id: prevButton
            width: 28
            height: 28
            radius: Dimensions.radius.small
            color: prevMouse.containsMouse
                ? Colors.stateLayer(Colors.onSurface, 0.10)
                : Colors.withAlpha(Colors.surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Text {
                anchors.centerIn: parent
                text: Icons.chevronLeft
                color: Colors.onSurfaceVariant
                font.family: Typography.iconFont
                font.pixelSize: 18
            }

            MouseArea {
                id: prevMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    optionRow.activated();
                    optionRow.previous();
                }
            }
        }

        Rectangle {
            id: valueChip
            width: 190
            height: 28
            radius: Dimensions.radius.small
            color: valueMouse.containsMouse
                ? Colors.withAlpha(Colors.surfaceContainerHighest, 0.95)
                : Colors.withAlpha(Colors.surfaceContainerHigh, 0.7)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.30)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: optionRow.value
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelLarge
                font.weight: Typography.weight.medium
            }

            MouseArea {
                id: valueMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    optionRow.activated();
                    optionRow.next();
                }
            }
        }

        Rectangle {
            id: nextButton
            width: 28
            height: 28
            radius: Dimensions.radius.small
            color: nextMouse.containsMouse
                ? Colors.stateLayer(Colors.onSurface, 0.10)
                : Colors.withAlpha(Colors.surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Text {
                anchors.centerIn: parent
                text: Icons.chevronRight
                color: Colors.onSurfaceVariant
                font.family: Typography.iconFont
                font.pixelSize: 18
            }

            MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    optionRow.activated();
                    optionRow.next();
                }
            }
        }
    }
}
