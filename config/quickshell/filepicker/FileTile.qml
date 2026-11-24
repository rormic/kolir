import QtQuick
import QtQuick.Window
import "../theme"

// One generic file/folder cell for FilePicker's GridView.  Folders keep the
// folder glyph and unsupported files (or a poster that is still generating or
// failed) keep the file-type icon.  Previewable images and videos show the
// lazy 16:9 poster the picker asks for in Component.onCompleted, so only tiles
// the grid actually instantiates ever decode a thumbnail.
Item {
    id: root

    required property string fileName
    required property string fileIcon
    required property string previewSource
    required property string previewKind
    required property bool selected
    required property bool checked
    required property bool folder
    required property bool multiple

    signal activated()
    signal previewRequested()

    readonly property int inset: 6
    readonly property int labelHeight: 28
    readonly property int iconSize: 44
    readonly property int checkSize: 22
    readonly property bool hovered: hover.hovered
    // Posters are generated at 480x270. Decoding only as many pixels as the
    // tile needs (scaled by the output's DPR) keeps scrolling cheap while
    // staying sharp, exactly like WallpaperTile.
    readonly property int thumbnailPixelWidth: 480
    readonly property bool hasPreview: !root.folder && root.previewSource !== ""
    readonly property bool video: root.previewKind === "video"

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
        clip: true

        // The cache path only contains a sha1 and an mtime, so building the
        // URL from it needs no escaping.
        Image {
            anchors.fill: parent
            visible: root.hasPreview
            source: root.hasPreview ? "file://" + root.previewSource : ""
            sourceSize.width: Math.min(
                root.thumbnailPixelWidth,
                Math.ceil(root.width * Screen.devicePixelRatio))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Text {
            anchors.centerIn: parent
            visible: !root.hasPreview
            text: root.fileIcon
            color: root.folder
                ? (root.selected || root.hovered
                    ? Colors.primary
                    : Colors.withAlpha(Colors.primary, 0.72))
                : Colors.withAlpha(Colors.onSurfaceVariant, 0.72)
            font.family: Typography.iconFont
            font.pixelSize: root.iconSize
        }

        // Video posters carry the same play badge as the wallpaper picker, so
        // a clip stays distinguishable from a still at a glance.
        Rectangle {
            anchors.centerIn: parent
            visible: root.hasPreview && root.video
            width: 38
            height: 38
            radius: width / 2
            color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.82)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

            Text {
                anchors.centerIn: parent
                text: Icons.playArrow
                color: Colors.onSurface
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.extraLarge
            }
        }

        // Multi-select check bubble.  It is only present when the portal
        // requested multiple files, so single-file dialogs stay uncluttered.
        // It stays above the poster.
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

    Component.onCompleted: {
        if (!root.folder)
            root.previewRequested();
    }
}
