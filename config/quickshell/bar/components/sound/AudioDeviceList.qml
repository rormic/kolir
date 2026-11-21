import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Scrollable device list with a header and an empty state, used for the
// output and input sections of the sound popup.
ColumnLayout {
    id: root

    property string title: ""
    property var model: []
    property string emptyIcon: ""
    property string emptyLabel: ""

    signal deviceActivated(string name)

    readonly property int deviceCount: model ? model.length : 0

    Layout.fillWidth: true
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
        }

        Text {
            text: root.deviceCount + (root.deviceCount === 1 ? " device" : " devices")
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 84
        radius: Dimensions.radius.medium
        color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
        clip: true

        ListView {
            id: deviceList

            anchors.fill: parent
            anchors.margins: 4
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.model

            delegate: Item {
                id: deviceRow

                required property var modelData

                width: deviceList.width
                height: 34

                readonly property bool hovered: deviceHover.hovered
                readonly property bool active: modelData.isDefault

                HoverHandler { id: deviceHover }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Dimensions.radius.small
                    color: deviceRow.active
                        ? Colors.withAlpha(Colors.primary, 0.14)
                        : deviceRow.hovered
                            ? Colors.stateLayer(Colors.onSurface, 0.06)
                            : "transparent"
                    border.width: deviceRow.active ? 1 : 0
                    border.color: Colors.withAlpha(Colors.primary, 0.45)

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    visible: deviceRow.active
                    text: Icons.check
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.medium
                }

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: deviceRow.active ? 36 : 12
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 0

                    Text {
                        width: parent.width
                        text: modelData.description || modelData.name || "Unknown device"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: deviceRow.active ? Typography.weight.bold : Typography.weight.medium
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!deviceRow.active)
                            root.deviceActivated(modelData.name);
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 6
            visible: deviceList.count === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.emptyIcon
                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                font.family: Typography.iconFont
                font.pixelSize: 24
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.emptyLabel
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
            }
        }
    }
}
