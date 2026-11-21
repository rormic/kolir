import QtQuick
import Quickshell
import "../theme"

// One launcher result row: app icon or clipboard index, image preview for
// clipboard images, selection highlight and the Enter hint. The launcher owns
// the model, selection and the action performed on click.
Item {
    id: root

    property var item: null
    property int itemIndex: 0
    property bool selected: false
    property bool clipboardMode: false
    property bool isImageClip: false
    property int rowHeight: 40

    signal activated()

    height: root.rowHeight

    Rectangle {
        id: rowBackground
        anchors.fill: parent
        anchors.margins: 2
        radius: Dimensions.radius.medium
        color: root.selected
            ? Colors.stateLayer(Colors.primary, 0.16)
            : itemMouse.containsMouse
                ? Colors.stateLayer(Colors.onSurface, 0.06)
                : "transparent"
        border.width: root.selected ? 1 : 0
        border.color: Colors.withAlpha(Colors.primary, 0.35)

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    // Акцент вибраного рядка
    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width: 2
        height: 18
        radius: 1
        visible: root.selected
        color: Colors.primary
    }

    Item {
        id: leading
        anchors {
            left: parent.left
            leftMargin: 14
            verticalCenter: parent.verticalCenter
        }
        width: 22
        height: 22

        Image {
            anchors.fill: parent
            visible: !root.clipboardMode
            sourceSize: Qt.size(20, 20)
            source: !root.clipboardMode
                ? Quickshell.iconPath(root.item.icon, "application-x-executable")
                : ""
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            visible: root.clipboardMode
            radius: Dimensions.radius.small
            color: root.selected
                ? Colors.primaryContainer
                : Colors.surfaceContainerHigh
            border.width: root.selected ? 0 : 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.18)

            Text {
                anchors.centerIn: parent
                text: root.itemIndex + 1
                color: root.selected
                    ? Colors.onPrimaryContainer
                    : Colors.primary
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                font.weight: Typography.weight.bold
            }
        }
    }

    // Прев'ю зображення з буфера обміну
    Rectangle {
        id: imageFrame
        anchors {
            left: leading.right
            leftMargin: 10
            verticalCenter: parent.verticalCenter
        }
        width: 152
        height: 100
        radius: Dimensions.radius.medium
        visible: root.isImageClip
        color: Colors.withAlpha(Colors.surfaceContainerLow, 0.55)
        border.width: 1
        border.color: root.selected
            ? Colors.withAlpha(Colors.primary, 0.35)
            : Colors.withAlpha(Colors.outlineVariant, 0.30)
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: 6
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false
            source: (root.isImageClip && root.item.imagePath !== "")
                ? ("file://" + root.item.imagePath) : ""
        }
    }

    // Метадані зображення
    Column {
        anchors {
            left: imageFrame.right
            leftMargin: 14
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        visible: root.isImageClip
        spacing: 4

        Text {
            width: parent.width
            text: root.item.imageDims || root.item.displayPreview || "Image"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: root.selected ? Typography.weight.bold : Typography.weight.medium
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.item.imageInfo || ""
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.selected
            text: "Enter to copy"
            color: Colors.primary
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            elide: Text.ElideRight
        }
    }

    // Назва програми або текст із буфера
    Text {
        anchors {
            left: leading.right
            leftMargin: 10
            right: enterHint.visible ? enterHint.left : parent.right
            rightMargin: enterHint.visible ? 8 : 14
            verticalCenter: parent.verticalCenter
        }
        visible: !root.isImageClip
        text: root.clipboardMode
            ? (root.item.displayPreview || root.item.preview)
            : root.item.name
        color: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.bodyMedium
        font.weight: root.selected ? Typography.weight.bold : Typography.weight.medium
        elide: Text.ElideRight
    }

    Text {
        id: enterHint
        anchors {
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        visible: root.selected && !root.isImageClip
        text: Icons.keyboardReturn
        color: Colors.primary
        font.family: Typography.iconFont
        font.pixelSize: 16
    }

    MouseArea {
        id: itemMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: root.activated()
    }
}
