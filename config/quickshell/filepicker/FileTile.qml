import QtQuick
import QtQuick.Window
import "../theme"

// One generic file/folder cell for FilePicker's GridView.  The tile is
// deliberately icon-first: the portal can ask for any directory, so decoding
// arbitrary images as thumbnails would make navigation sluggish.
Item {
    id: root

    required property string fileName
    required property string fileIcon
    required property bool selected
    required property bool checked
    required property bool folder
    required property bool multiple

    signal activated()

    readonly property int inset: 6
    readonly property int labelHeight: 28
    readonly property int iconSize: 44
    readonly property int checkSize: 22
    readonly property bool hovered: hover.hovered

    HoverHandler {
        id: hover
    }

    implicitWidth: 220
    implicitHeight: 156

    Rectangle {
        id: frame

        anchors.fill: parent
        radius: Dimensions.radius.medium
        color: root.selected
            ? Colors.stateLayer(Colors.primary, 0.16)
            : root.hovered
                ? Colors.stateLayer(Colors.primary, 0.09)
                : Colors.surfaceContainerHigh
        border.width: root.selected ? 2 : 1
        border.color: root.selected
            ? Colors.primary
            : root.hovered
                ? Colors.withAlpha(Colors.primary, 0.5)
                : Colors.withAlpha(Colors.outlineVariant, 0.22)

        Behavior on color { ColorAnimation { duration: Motion.hover } }
        Behavior on border.color { ColorAnimation { duration: Motion.hover } }
    }

    Item {
        id: preview

        anchors {
            top: frame.top
            left: frame.left
            right: frame.right
            bottom: label.top
            margins: root.inset
            bottomMargin: root.inset / 2
        }

        Text {
            anchors.centerIn: parent
            text: root.fileIcon
            color: root.folder
                ? (root.selected || root.hovered
                    ? Colors.primary
                    : Colors.withAlpha(Colors.primary, 0.72))
                : Colors.withAlpha(Colors.onSurfaceVariant, 0.72)
            font.family: Typography.iconFont
            font.pixelSize: root.iconSize
        }

        // Multi-select check bubble.  It is only present when the portal
        // requested multiple files, so single-file dialogs stay uncluttered.
        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
            }
            width: root.checkSize
            height: root.checkSize
            radius: width / 2
            visible: root.multiple
            color: root.checked
                ? Colors.primary
                : Colors.withAlpha(Colors.surfaceContainerHighest, 0.92)
            border.width: 1
            border.color: root.checked
                ? Colors.primary
                : Colors.withAlpha(Colors.outline, 0.55)

            Text {
                anchors.centerIn: parent
                visible: root.checked
                text: Icons.check
                color: Colors.onPrimary
                font.family: Typography.iconFont
                font.pixelSize: 14
            }
        }
    }

    Text {
        id: label

        anchors {
            left: frame.left
            right: frame.right
            bottom: frame.bottom
            leftMargin: root.inset + 2
            rightMargin: root.inset + 2
            bottomMargin: root.inset
        }
        height: root.labelHeight
        verticalAlignment: Text.AlignVCenter
        text: root.fileName
        color: root.selected || root.hovered ? Colors.onSurface : Colors.onSurfaceVariant
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
        font.weight: root.selected || root.hovered
            ? Typography.weight.medium
            : Typography.weight.regular
        elide: Text.ElideMiddle
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
