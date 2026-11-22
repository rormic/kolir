import QtQuick
import "../theme"

// One wallpaper cell: cached 16:9 thumbnail, file name and the keyboard/mouse
// selection highlight used by WallpaperPicker's GridView.
Item {
    id: root

    required property string thumbnailSource
    required property string fileName
    required property bool selected

    signal activated()
    signal hovered()

    readonly property int inset: 6
    readonly property int labelHeight: 28
    // Previews are generated at 480x270; decoding them at that width keeps
    // the grid sharp without touching the full-size source.
    readonly property int thumbnailPixelWidth: 480

    implicitWidth: 220
    implicitHeight: 170

    Rectangle {
        id: frame

        anchors.fill: parent
        radius: Dimensions.radius.medium
        color: root.selected
            ? Colors.stateLayer(Colors.primary, 0.16)
            : Colors.surfaceContainerHigh
        border.width: root.selected ? 2 : 1
        border.color: root.selected
            ? Colors.primary
            : Colors.withAlpha(Colors.outlineVariant, 0.22)

        Behavior on color { ColorAnimation { duration: Motion.color } }
        Behavior on border.color { ColorAnimation { duration: Motion.color } }
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
        clip: true

        Image {
            anchors.fill: parent
            source: root.thumbnailSource !== "" ? "file://" + root.thumbnailSource : ""
            sourceSize.width: root.thumbnailPixelWidth
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: root.thumbnailSource !== ""
        }

        Text {
            anchors.centerIn: parent
            visible: root.thumbnailSource === ""
            text: Icons.wallpaper
            color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.extraLarge
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
        color: root.selected ? Colors.onSurface : Colors.onSurfaceVariant
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
        font.weight: root.selected ? Typography.weight.medium : Typography.weight.regular
        elide: Text.ElideMiddle
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        onClicked: root.activated()
    }
}
