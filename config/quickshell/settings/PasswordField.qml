import QtQuick
import QtQuick.Layouts
import "../theme"
import "../bar/components"

// Shared masked text field for the Wi-Fi forms. It owns the echo mode,
// visibility button, selection and Return/Enter/Escape handling; the owning
// form decides what submission and cancellation mean.
Rectangle {
    id: root

    property alias text: input.text
    property bool showPassword: false
    property string placeholder: ""

    signal visibilityToggled()
    signal submitRequested()
    signal cancelRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: Dimensions.radius.small
    color: Colors.surfaceContainerLowest
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.4)

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
        spacing: 4

        TextInput {
            id: input

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            clip: true
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            Keys.onReturnPressed: root.submitRequested()
            Keys.onEnterPressed: root.submitRequested()
            Keys.onEscapePressed: root.cancelRequested()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.placeholder !== "" && !parent.text && !parent.activeFocus
                text: root.placeholder
                color: Colors.onSurfaceVariant
                font: parent.font
            }
        }

        IconButton {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            icon: root.showPassword ? Icons.visibilityOff : Icons.visibility
            iconSize: Dimensions.icon.small + 2
            onClicked: root.visibilityToggled()
        }
    }
}
