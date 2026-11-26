import QtQuick
import QtQuick.Window
import "../bar/components"
import "../theme"

// One capture card: cached 16:9 poster, file name, time, a video badge and the
// hover actions (copy, open, delete). Delete is confirmed on the card itself so
// no dialog window has to take focus away from the grid.
Item {
    id: root

    required property string path
    required property string thumb
    required property string kind
    required property real mtime
    required property string fileName
    required property bool selected

    // Set by the grid while this card is waiting for a second Delete press.
    property bool confirmingDelete: false

    signal activated()
    signal copyRequested()
    signal deleteRequested()
    signal cancelDelete()

    readonly property int inset: 6
    readonly property int labelHeight: 40
    readonly property bool video: root.kind === "video"
    readonly property bool hovered: hover.hovered
    readonly property int thumbnailPixelWidth: 480

    implicitWidth: 220
    implicitHeight: 170

    HoverHandler {
        id: hover
    }

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

        Behavior on color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
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
            source: root.thumb !== "" ? "file://" + root.thumb : ""
            sourceSize.width: Math.min(
                root.thumbnailPixelWidth,
                Math.ceil(root.width * Screen.devicePixelRatio))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: root.thumb !== ""
        }

        Text {
            anchors.centerIn: parent
            visible: root.thumb === ""
            text: root.video ? Icons.movie : Icons.image
            color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.extraLarge
        }

        // Video badge: the poster is a still frame, so the type needs an
        // explicit marker.
        Rectangle {
            anchors {
                left: parent.left
                bottom: parent.bottom
                margins: 6
            }
            visible: root.video
            width: 22
            height: 22
            radius: width / 2
            color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.8)

            Text {
                anchors.centerIn: parent
                text: Icons.playArrow
                color: Colors.onPrimaryContainer
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.small
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
        }

        Rectangle {
            id: actionBar

            anchors {
                top: parent.top
                right: parent.right
                margins: 4
            }
            visible: root.hovered || root.selected
            width: actionRow.implicitWidth + 4
            height: 26
            radius: Dimensions.radius.full
            color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.82)

            Row {
                id: actionRow

                anchors.centerIn: parent
                spacing: 0

                IconButton {
                    width: 24
                    height: 24
                    icon: Icons.contentCopy
                    iconSize: Dimensions.icon.small
                    iconColor: Colors.onSurface
                    onClicked: root.copyRequested()
                }

                IconButton {
                    width: 24
                    height: 24
                    icon: Icons.openInNew
                    iconSize: Dimensions.icon.small
                    iconColor: Colors.onSurface
                    onClicked: root.activated()
                }

                IconButton {
                    width: 24
                    height: 24
                    icon: Icons.trash
                    iconSize: Dimensions.icon.small
                    iconColor: Colors.onSurfaceVariant
                    onClicked: root.deleteRequested()
                }
            }
        }

        // Confirmation replaces the poster instead of opening a dialog, so the
        // grid keeps keyboard focus and Escape cancels in place.
        Rectangle {
            anchors.fill: parent
            visible: root.confirmingDelete
            color: Colors.withAlpha(Colors.surfaceContainerLow, 0.94)
            radius: Dimensions.radius.small

            MouseArea {
                anchors.fill: parent
            }

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Delete this file?"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Rectangle {
                        width: 64
                        height: 24
                        radius: Dimensions.radius.full
                        color: Colors.errorContainer

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: Colors.onErrorContainer
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.deleteRequested()
                        }
                    }

                    Rectangle {
                        width: 64
                        height: 24
                        radius: Dimensions.radius.full
                        color: Colors.surfaceContainerHighest
                        border.width: 1
                        border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelDelete()
                        }
                    }
                }
            }
        }

    }

    Column {
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
        spacing: 1

        Text {
            width: parent.width
            text: root.fileName
            color: root.selected || root.hovered ? Colors.onSurface : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: root.selected || root.hovered
                ? Typography.weight.medium
                : Typography.weight.regular
            elide: Text.ElideMiddle
        }

        Text {
            width: parent.width
            text: (root.video ? "Video" : "Image") + " · "
                + Qt.formatDateTime(new Date(root.mtime * 1000), "d MMM, HH:mm")
            color: Colors.withAlpha(Colors.onSurfaceVariant, 0.75)
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            elide: Text.ElideRight
        }
    }
}
