import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../bar/components"
import "../theme"

// One notification card in the overlay stack. The notification server and
// the overlay window stay in Notification.qml.
Surface {
    id: root

    required property Notification modelData
    required property int index

    readonly property color fg: Colors.onSurface
    readonly property color accent: Colors.primary
    readonly property color critical: Colors.error

    readonly property bool isCritical: modelData.urgency === NotificationUrgency.Critical

    implicitHeight: content.implicitHeight + 24

    radius: Dimensions.radius.large
    surfaceColor: hover.hovered
        ? Colors.withAlpha(Colors.surfaceContainerHigh, 0.96)
        : Colors.withAlpha(Colors.surfaceContainerLow, 0.96)
    borderWidth: 1
    borderColor: isCritical
        ? Colors.withAlpha(root.critical, 0.55)
        : hover.hovered
            ? Colors.withAlpha(root.accent, 0.65)
            : Colors.withAlpha(root.accent, 0.4)

    // Поява карточки з верхнього правого кута
    property real appear: 0
    opacity: appear
    scale: 0.97 + 0.03 * appear
    transformOrigin: Item.TopRight

    SequentialAnimation {
        id: appearAnim

        PauseAnimation {
            duration: Math.max(0, Math.min((root.index >= 0 ? root.index : 0) * 50, 300))
        }
        NumberAnimation {
            target: root
            property: "appear"
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Component.onCompleted: appearAnim.start()

    // Автозакриття: критичні лишаються, поки не закриєш вручну
    Timer {
        running: !root.isCritical && !hover.hovered
        interval: root.modelData.expireTimeout > 0 ? root.modelData.expireTimeout * 1000 : 5000
        onTriggered: root.modelData.expire()
    }

    HoverHandler {
        id: hover
    }

    // Клік по картці закриває її
    TapHandler {
        onTapped: root.modelData.dismiss()
    }

    Column {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 6

        // Шапка: іконка застосунку + назва
        Row {
            id: header
            width: parent.width
            spacing: 8

            Image {
                id: appIcon

                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: status === Image.Ready
                source: !root.modelData.appIcon
                    ? ""
                    : (root.modelData.appIcon.startsWith("/")
                        ? root.modelData.appIcon
                        : Quickshell.iconPath(root.modelData.appIcon, "application-x-executable"))
                sourceSize: Qt.size(16, 16)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: header.width - (appIcon.visible ? appIcon.width + header.spacing : 0)
                text: root.modelData.appName
                color: root.isCritical ? root.critical : root.accent
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.medium
                elide: Text.ElideRight
            }
        }

        // Тема повідомлення
        Text {
            width: parent.width
            text: root.modelData.summary
            color: root.fg
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: Typography.weight.bold
            wrapMode: Text.Wrap
        }

        // Тіло повідомлення
        Text {
            visible: text !== ""
            width: parent.width
            text: root.modelData.body
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        // Кнопки дій у стилі бару
        Row {
            spacing: 6
            visible: root.modelData.actions.length > 0

            Repeater {
                model: root.modelData.actions

                delegate: Pill {
                    required property var modelData

                    text: modelData.text
                    textSize: Typography.size.labelSmall
                    textWeight: Typography.weight.medium
                    horizontalPadding: Dimensions.padding.chipHorizontal

                    TapHandler {
                        onTapped: modelData.invoke()
                    }
                }
            }
        }
    }
}
