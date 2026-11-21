pragma ComponentBehavior: Bound

import QtQuick
import "../../../theme"

// Time value with hour/minute steppers for the night-light schedule. The
// owner supplies the current value and receives the normalized result; hour
// steps move by a full hour, minute steps by five minutes, and both wrap
// around midnight.
Item {
    id: timeField

    property string label: ""
    property int hour: 0
    property int minute: 0
    property bool interactive: true

    signal edited(int hour, int minute)

    readonly property int minutesPerHour: 60
    readonly property int minuteStep: 5
    readonly property int minutesPerDay: 1440

    implicitWidth: 150
    implicitHeight: 96

    function applyTotal(total) {
        const wrapped = ((total % timeField.minutesPerDay) + timeField.minutesPerDay)
            % timeField.minutesPerDay;
        timeField.edited(Math.floor(wrapped / timeField.minutesPerHour),
            wrapped % timeField.minutesPerHour);
    }

    function stepHour(delta) {
        timeField.applyTotal(timeField.hour * timeField.minutesPerHour
            + timeField.minute + delta * timeField.minutesPerHour);
    }

    function stepMinute(delta) {
        timeField.applyTotal(timeField.hour * timeField.minutesPerHour
            + timeField.minute + delta * timeField.minuteStep);
    }

    component StepButton: Item {
        id: stepButton

        property string icon: ""
        property bool interactive: true

        signal clicked()

        width: 30
        height: 18
        opacity: stepButton.interactive ? 1.0 : 0.35

        Text {
            anchors.centerIn: parent
            text: stepButton.icon
            color: stepMouse.containsMouse
                ? Colors.primary
                : Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.large

            Behavior on color { ColorAnimation { duration: 100 } }
        }

        MouseArea {
            id: stepMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: stepButton.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: stepButton.clicked()
        }
    }

    component TimeColumn: Item {
        id: timeColumn

        property int value: 0
        property bool interactive: true

        signal step(int delta)

        width: 36
        height: 60

        Column {
            anchors.centerIn: parent
            spacing: 0

            StepButton {
                icon: Icons.chevronUp
                interactive: timeColumn.interactive
                onClicked: timeColumn.step(1)
            }

            Text {
                width: parent.width
                height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: timeColumn.value < 10 ? "0" + timeColumn.value : String(timeColumn.value)
                color: timeColumn.interactive ? Colors.onSurface : Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.bold
            }

            StepButton {
                icon: Icons.chevronDown
                interactive: timeColumn.interactive
                onClicked: timeColumn.step(-1)
            }
        }

        WheelHandler {
            enabled: timeColumn.interactive
            onWheel: wheel => {
                if (wheel.angleDelta.y === 0)
                    return;

                timeColumn.step(wheel.angleDelta.y > 0 ? 1 : -1);
                wheel.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Dimensions.radius.medium
        color: Colors.surfaceContainerLowest
        border.width: 1
        border.color: timeHover.hovered
            ? Colors.withAlpha(Colors.primary, 0.35)
            : Colors.withAlpha(Colors.outlineVariant, 0.3)

        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    HoverHandler {
        id: timeHover
        enabled: timeField.interactive
    }

    Column {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 2

        Text {
            width: parent.width
            text: timeField.label
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            TimeColumn {
                value: timeField.hour
                interactive: timeField.interactive
                onStep: delta => timeField.stepHour(delta)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ":"
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.bold
            }

            TimeColumn {
                value: timeField.minute
                interactive: timeField.interactive
                onStep: delta => timeField.stepMinute(delta)
            }
        }
    }
}
