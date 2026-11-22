import QtQuick
import QtQuick.Layouts
import "../bar/components"
import "../services"
import "../theme"

// Keep-awake card on the settings main page. The switch owns the indefinite
// mode; the preset chips start (or restart) a timed session.
Rectangle {
    id: root

    implicitHeight: content.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: CaffeineService.enabled
        ? Colors.withAlpha(Colors.primary, 0.35)
        : Colors.withAlpha(Colors.outlineVariant, 0.22)

    Behavior on border.color { ColorAnimation { duration: Motion.hover } }

    ColumnLayout {
        id: content

        anchors {
            fill: parent
            margins: 12
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                radius: Dimensions.radius.small + 2
                color: CaffeineService.enabled
                    ? Colors.primaryContainer
                    : Colors.surfaceContainerHighest

                Behavior on color { ColorAnimation { duration: Motion.color } }

                Text {
                    anchors.centerIn: parent
                    text: Icons.caffeine
                    color: CaffeineService.enabled
                        ? Colors.onPrimaryContainer
                        : Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Keep awake"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.bodyMedium
                    font.weight: Typography.weight.medium
                }

                Text {
                    Layout.fillWidth: true
                    text: CaffeineService.statusText
                    color: CaffeineService.enabled
                        ? Colors.primary
                        : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }

            Toggle {
                Layout.alignment: Qt.AlignVCenter
                checked: CaffeineService.enabled
                onToggled: value => {
                    if (value)
                        CaffeineService.enable(0);
                    else
                        CaffeineService.disable();
                }
            }
        }

        Row {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { label: "15 min", minutes: 15 },
                    { label: "30 min", minutes: 30 },
                    { label: "1 h", minutes: 60 },
                    { label: "∞", minutes: 0 },
                ]

                delegate: Rectangle {
                    id: chip

                    required property var modelData

                    readonly property bool selected: CaffeineService.enabled
                        && (chip.modelData.minutes === 0
                            ? CaffeineService.until === 0
                            : CaffeineService.presetMinutes === chip.modelData.minutes)
                    readonly property bool hovered: chipMouse.containsMouse

                    width: chipLabel.implicitWidth + 16
                    height: 24
                    radius: Dimensions.radius.full
                    color: Colors.surfaceContainerHighest
                    border.width: 1
                    border.color: chip.selected
                        ? Colors.withAlpha(Colors.primary, 0.7)
                        : chip.hovered
                            ? Colors.withAlpha(Colors.primary, 0.45)
                            : Colors.withAlpha(Colors.outlineVariant, 0.25)

                    Behavior on color { ColorAnimation { duration: Motion.hover } }
                    Behavior on border.color { ColorAnimation { duration: Motion.hover } }

                    // Selected/hover state layer. Fading an own fill avoids a
                    // colour transition from an opaque chip to a translucent
                    // state layer, which would flash through opaque grey.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: chip.selected
                            ? Colors.withAlpha(Colors.primary, 0.22)
                            : Colors.stateLayer(Colors.primary, 0.12)
                        opacity: chip.selected || chip.hovered ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.hover
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Text {
                        id: chipLabel

                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: chip.selected
                            ? Colors.primary
                            : chip.hovered
                                ? Colors.primary
                                : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: Typography.weight.medium
                    }

                    MouseArea {
                        id: chipMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: CaffeineService.enable(chip.modelData.minutes)
                    }
                }
            }
        }
    }
}
