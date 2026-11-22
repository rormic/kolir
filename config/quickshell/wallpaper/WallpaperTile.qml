import QtQuick
import QtQuick.Window
import "../theme"

// One wallpaper cell: cached 16:9 thumbnail, file name and the keyboard/mouse
// selection highlight used by WallpaperPicker's GridView.
Item {
    id: root

    required property string thumbnailSource
    required property string fileName
    required property bool selected
    required property bool folder

    signal activated()

    readonly property int inset: 6
    readonly property int labelHeight: 28
    // Previews are generated at 480x270. Decoding only as many pixels as the
    // tile needs (scaled by the output's DPR) keeps scrolling cheap while
    // staying sharp; the full preview bitmap is never decoded.
    readonly property int thumbnailPixelWidth: 480
    readonly property int folderIconSize: 42

    // Hover is visual feedback; the selected tile follows it only when the
    // grid is stationary, so scrolling under a fixed cursor cannot churn the
    // selection. hoveredIndex survives a scroll and is applied when it stops.
    readonly property bool hovered: hover.hovered

    HoverHandler {
        id: hover
    }

    implicitWidth: 220
    implicitHeight: 170

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
        clip: true

        Image {
            anchors.fill: parent
            source: root.thumbnailSource !== "" ? "file://" + root.thumbnailSource : ""
            sourceSize.width: Math.min(
                root.thumbnailPixelWidth,
                Math.ceil(root.width * Screen.devicePixelRatio))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !root.folder && root.thumbnailSource !== ""
        }

        Text {
            anchors.centerIn: parent
            visible: root.folder
            text: Icons.folder
            color: root.selected || root.hovered
                ? Colors.primary
                : Colors.withAlpha(Colors.primary, 0.72)
            font.family: Typography.iconFont
            font.pixelSize: root.folderIconSize
        }

        Text {
            anchors.centerIn: parent
            visible: !root.folder && root.thumbnailSource === ""
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
