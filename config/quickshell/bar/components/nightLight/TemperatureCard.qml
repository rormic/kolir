pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import ".."

// Temperature slider card for the night-light popup. The card keeps a local
// slider position while dragging, so the handle follows the cursor without
// waiting for hyprctl to confirm every step; the settle timer releases it
// after wheel changes.
Rectangle {
    id: root

    property int temperature: 4000
    property int minTemperature: 2000
    property int maxTemperature: 6500
    property bool interactive: true

    signal temperatureRequested(int kelvin)

    property bool dragging: false
    property real dragPercent: 0

    readonly property int displayTemperature: root.dragging
        ? root.percentToTemperature(root.dragPercent)
        : root.temperature

    function temperatureToPercent(kelvin) {
        const range = root.maxTemperature - root.minTemperature;
        if (range <= 0)
            return 0;

        return Math.max(0, Math.min(100,
            (kelvin - root.minTemperature) / range * 100));
    }

    function percentToTemperature(percent) {
        const range = root.maxTemperature - root.minTemperature;
        const raw = root.minTemperature + percent / 100 * range;
        return Math.max(root.minTemperature,
            Math.min(root.maxTemperature, Math.round(raw / 50) * 50));
    }

    function cancelDrag() {
        root.dragging = false;
        temperatureSettleTimer.stop();
    }

    Timer {
        id: temperatureSettleTimer

        interval: 350
        repeat: false
        onTriggered: root.dragging = false
    }

    Layout.fillWidth: true
    implicitHeight: temperatureColumn.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    ColumnLayout {
        id: temperatureColumn

        anchors {
            fill: parent
            margins: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Temperature"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.bold
            }

            Text {
                text: root.displayTemperature + " K"
                color: Colors.primary
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.bold
            }
        }

        VolumeSlider {
            Layout.fillWidth: true
            value: root.dragging
                ? root.dragPercent
                : root.temperatureToPercent(root.temperature)
            interactive: root.interactive
            onDragStarted: value => {
                temperatureSettleTimer.stop();
                root.dragging = true;
                root.dragPercent = value;
                root.temperatureRequested(root.percentToTemperature(value));
            }
            onDragUpdated: value => {
                root.dragPercent = value;
                root.temperatureRequested(root.percentToTemperature(value));
            }
            onMoved: value => {
                root.dragPercent = value;
                root.dragging = false;
                root.temperatureRequested(root.percentToTemperature(value));
            }
            onWheelMoved: value => {
                root.dragging = true;
                root.dragPercent = value;
                root.temperatureRequested(root.percentToTemperature(value));
                temperatureSettleTimer.restart();
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [2500, 4000, 6500]

                delegate: Rectangle {
                    id: presetChip

                    required property int modelData

                    readonly property bool active: root.temperature === modelData
                    readonly property bool hovered: presetMouse.containsMouse

                    Layout.fillWidth: true
                    implicitHeight: 28
                    opacity: root.interactive ? 1.0 : 0.45
                    radius: Dimensions.radius.full
                    color: presetChip.active
                        ? Colors.primaryContainer
                        : Colors.surfaceContainerLowest
                    border.width: 1
                    border.color: presetChip.active
                        ? Colors.withAlpha(Colors.primary, 0.7)
                        : Colors.withAlpha(Colors.outlineVariant, 0.35)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    StateLayer {
                        shown: presetChip.hovered && !presetChip.active
                        strength: 0.12
                        duration: Motion.fade
                    }

                    Text {
                        anchors.centerIn: parent
                        text: presetChip.modelData + " K"
                        color: presetChip.active
                            ? Colors.onPrimaryContainer
                            : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: presetChip.active
                            ? Typography.weight.bold
                            : Typography.weight.medium
                    }

                    MouseArea {
                        id: presetMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.temperatureRequested(presetChip.modelData)
                    }
                }
            }
        }
    }
}
