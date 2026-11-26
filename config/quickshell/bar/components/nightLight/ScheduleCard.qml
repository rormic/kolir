pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import ".."

// Automatic schedule card for the night-light popup: schedule toggle, mode
// chips, fixed time steppers and the sunrise/sunset location block.
Rectangle {
    id: root

    readonly property string scheduleWarning: {
        if (HyprsunsetService.scheduleValid)
            return "";

        if (HyprsunsetService.scheduleMode === "sun") {
            if (HyprsunsetService.locationRefreshing)
                return "";
            if (!HyprsunsetService.locationAvailable)
                return "Location unavailable — refresh or use fixed times";
            return "Sunrise/sunset unavailable for this date";
        }

        return "On and off times must differ";
    }

    Layout.fillWidth: true
    implicitHeight: scheduleColumn.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: HyprsunsetService.scheduleActive
        ? Colors.withAlpha(Colors.primary, 0.35)
        : Colors.withAlpha(Colors.outlineVariant, 0.22)

    Behavior on border.color {
        ColorAnimation {
            duration: Motion.color
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.standardDecelerateCurve
        }
    }

    ColumnLayout {
        id: scheduleColumn

        anchors {
            fill: parent
            margins: 12
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter
                radius: Dimensions.radius.small
                color: HyprsunsetService.scheduleActive
                    ? Colors.primaryContainer
                    : Colors.surfaceContainerHighest

                Text {
                    anchors.centerIn: parent
                    text: Icons.schedule
                    color: HyprsunsetService.scheduleActive
                        ? Colors.onPrimaryContainer
                        : Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Automatic schedule"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }

                Text {
                    Layout.fillWidth: true
                    text: HyprsunsetService.scheduleStatusText
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }

            Toggle {
                Layout.alignment: Qt.AlignVCenter
                checked: HyprsunsetService.autoSchedule
                interactive: HyprsunsetService.available
                    && HyprsunsetService.scheduleValid
                onToggled: checked => HyprsunsetService.setScheduleEnabled(checked)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ModeChip {
                Layout.fillWidth: true
                text: "Fixed times"
                active: HyprsunsetService.scheduleMode === "fixed"
                onClicked: HyprsunsetService.setScheduleMode("fixed")
            }

            ModeChip {
                Layout.fillWidth: true
                text: "Sunrise / sunset"
                active: HyprsunsetService.scheduleMode === "sun"
                onClicked: HyprsunsetService.setScheduleMode("sun")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: HyprsunsetService.scheduleMode === "fixed"

            TimeField {
                Layout.fillWidth: true
                label: "Turn on"
                hour: HyprsunsetService.onHour
                minute: HyprsunsetService.onMinute
                interactive: HyprsunsetService.available
                onEdited: (hour, minute) => HyprsunsetService.setOnTime(hour, minute)
            }

            TimeField {
                Layout.fillWidth: true
                label: "Turn off"
                hour: HyprsunsetService.offHour
                minute: HyprsunsetService.offMinute
                interactive: HyprsunsetService.available
                onEdited: (hour, minute) => HyprsunsetService.setOffTime(hour, minute)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: HyprsunsetService.scheduleMode === "sun"

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: Icons.place
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: "Location"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: Typography.weight.medium
                    }

                    Text {
                        Layout.fillWidth: true
                        text: HyprsunsetService.locationLabel
                        color: HyprsunsetService.locationAvailable
                            ? Colors.onSurface
                            : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon: Icons.refresh
                    iconSize: Dimensions.icon.small + 2
                    enabled: !HyprsunsetService.locationRefreshing
                    opacity: HyprsunsetService.locationRefreshing ? 0.5 : 1.0
                    onClicked: HyprsunsetService.refreshLocation(true)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SunTimeCard {
                    Layout.fillWidth: true
                    icon: Icons.lightMode
                    caption: "Sunrise"
                    value: HyprsunsetService.sunriseLabel
                }

                SunTimeCard {
                    Layout.fillWidth: true
                    icon: Icons.darkMode
                    caption: "Sunset"
                    value: HyprsunsetService.sunsetLabel
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.scheduleWarning !== ""
            text: root.scheduleWarning
            color: Colors.error
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            wrapMode: Text.Wrap
        }
    }

    component ModeChip: Rectangle {
        id: modeChip

        property string text: ""
        property bool active: false

        signal clicked()

        readonly property bool hovered: modeMouse.containsMouse

        implicitHeight: 26
        radius: Dimensions.radius.full
        color: modeChip.active
            ? Colors.primaryContainer
            : Colors.surfaceContainerLowest
        border.width: 1
        border.color: modeChip.active
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

        // Same Material 3 spatial spring as the temperature presets, so the
        // whole sheet speaks one motion language.
        scale: modeChip.active ? 1.02 : 1.0
        Behavior on scale {
            SpringAnimation {
                spring: Motion.spatialSpring
                damping: Motion.spatialSpringDamping
                epsilon: Motion.springScaleEpsilon
            }
        }

        StateLayer {
            shown: modeChip.hovered && !modeChip.active
            strength: 0.12
            duration: Motion.fade
        }

        Text {
            anchors.centerIn: parent
            text: modeChip.text
            color: modeChip.active ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: modeChip.active ? Typography.weight.bold : Typography.weight.medium
        }

        MouseArea {
            id: modeMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: HyprsunsetService.available
            cursorShape: Qt.PointingHandCursor
            onClicked: modeChip.clicked()
        }
    }
}
