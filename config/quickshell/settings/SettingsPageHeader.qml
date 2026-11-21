import QtQuick
import "../theme"
import "../bar/components"

// Shared header for the settings subpages: back button, title, divider and
// the top inset used while the settings popout is revealing.
Item {
    id: root

    signal back()

    property string title: ""
    property int topInset: 0

    anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        topMargin: root.topInset
    }
    height: 46

    Rectangle {
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
    }

    IconButton {
        id: backButton

        anchors {
            left: parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        icon: Icons.arrowBack
        iconSize: Dimensions.icon.medium
        onClicked: root.back()
    }

    Text {
        anchors {
            left: backButton.right
            leftMargin: 2
            verticalCenter: parent.verticalCenter
        }
        text: root.title
        color: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.titleLarge
        font.weight: Typography.weight.bold
    }
}
