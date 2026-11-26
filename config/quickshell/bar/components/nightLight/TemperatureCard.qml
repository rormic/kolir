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

    // VolumeSlider writes its own `value` while dragging, which tears down a
    // plain `value:` binding on the first interaction. Push the service value
    // explicitly instead, or presets and IPC changes would stop moving the
    // handle after the first drag.
    function syncSlider() {
        temperatureSlider.value = root.temperatureToPercent(root.temperature);
    }

    onTemperatureChanged: {
        if (root.dragging)
            return;
        root.syncSlider();
    }

    Component.onCompleted: root.syncSlider()

    Timer {
        id: temperatureSettleTimer

        interval: 350
        repeat: false
        onTriggered: {
            root.dragging = false;
            // Settle on the rounded service step with the spring instead of
            // leaving the handle on the raw wheel percentage.
            root.syncSlider();
        }
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
                id: temperatureValue

                text: root.displayTemperature + " K"
                color: Colors.primary
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.bold

                // Material 3 timing for a small value change: the label leaves
                // on duration-short1 with the emphasized accelerate curve and
                // returns on duration-short2 with emphasized decelerate. The
                // 0.95 dip is an optical amplitude; M3 defines the motion, not
                // a text pulse.
                onTextChanged: if (!root.dragging)
                    temperaturePulse.restart()

                SequentialAnimation {
                    id: temperaturePulse

                    NumberAnimation {
                        target: temperatureValue
                        property: "scale"
                        to: 0.95
                        duration: Motion.durationShort1
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Motion.emphasizedAccelerateCurve
                    }

                    NumberAnimation {
                        target: temperatureValue
                        property: "scale"
                        to: 1.0
                        duration: Motion.durationShort2
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Motion.emphasizedDecelerateCurve
                    }
                }
            }
        }

        VolumeSlider {
            id: temperatureSlider

            Layout.fillWidth: true
            springValue: true
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

                    // Material 3 Expressive spatial spring for the selected
                    // preset. The 1.02 lift is an optical cue, the overshoot
                    // and settle come from the M3 spring (damping ratio 0.8).
                    scale: presetChip.active ? 1.02 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: Motion.spatialSpring
                            damping: Motion.spatialSpringDamping
                            epsilon: Motion.springScaleEpsilon
                        }
                    }

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
                        onClicked: {
                            // A preset replaces the wheel preview: release
                            // it first so the service answer can settle the
                            // handle on the selected step.
                            root.cancelDrag();
                            root.temperatureRequested(presetChip.modelData);
                        }
                    }
                }
            }
        }
    }
}
