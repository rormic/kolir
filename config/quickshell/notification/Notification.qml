import "../bar/components"
import "../theme"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
    id: root

    readonly property color fg: Colors.onSurface
    readonly property color accent: Colors.primary
    readonly property color critical: Colors.error

    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        keepOnReload: true

        onNotification: n => {
            n.tracked = true
        }
    }

    PanelWindow {
        id: win
        visible: server.trackedNotifications.values.length > 0
        color: "transparent"

        anchors {
            top: true
            right: true
        }
        margins {
            top: Dimensions.bar.height + Dimensions.bar.margin + 8
            right: 12
        }

        implicitWidth: 380
        implicitHeight: col.implicitHeight

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"

        Column {
            id: col
            width: parent.width
            spacing: 8

            Repeater {
                model: server.trackedNotifications

                delegate: Surface {
                    id: card

                    required property Notification modelData
                    required property int index

                    readonly property bool isCritical: modelData.urgency === NotificationUrgency.Critical

                    width: col.width
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
                            duration: Math.max(0, Math.min((card.index >= 0 ? card.index : 0) * 50, 300))
                        }
                        NumberAnimation {
                            target: card
                            property: "appear"
                            to: 1
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    Component.onCompleted: appearAnim.start()

                    // Автозакриття: критичні лишаються, поки не закриєш вручну
                    Timer {
                        running: !card.isCritical && !hover.hovered
                        interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : 5000
                        onTriggered: card.modelData.expire()
                    }

                    HoverHandler {
                        id: hover
                    }

                    // Клік по картці закриває її
                    TapHandler {
                        onTapped: card.modelData.dismiss()
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
                                source: !card.modelData.appIcon
                                    ? ""
                                    : (card.modelData.appIcon.startsWith("/")
                                        ? card.modelData.appIcon
                                        : Quickshell.iconPath(card.modelData.appIcon, "application-x-executable"))
                                sourceSize: Qt.size(16, 16)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: header.width - (appIcon.visible ? appIcon.width + header.spacing : 0)
                                text: card.modelData.appName
                                color: card.isCritical ? root.critical : root.accent
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: Typography.weight.medium
                                elide: Text.ElideRight
                            }
                        }

                        // Тема повідомлення
                        Text {
                            width: parent.width
                            text: card.modelData.summary
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
                            text: card.modelData.body
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
                            visible: card.modelData.actions.length > 0

                            Repeater {
                                model: card.modelData.actions

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
            }
        }
    }
}
