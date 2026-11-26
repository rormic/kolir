import QtQuick
import Quickshell
import "../../theme"

// Clock: date, time and keyboard layout drawn directly on the bar strip.
//
// The clock is information, not a menu. It used to sit in a filled pill like
// the brightness/volume chips, which made it look clickable while it did
// nothing; the flat layout keeps the pill reserved for controls. The date is
// the one exception: it carries a hover state layer and opens the calendar
// sheet, while the time and layout labels stay inert. The reserved width still
// mirrors the now-playing island so the workspaces pill stays centered.
Item {
    id: root

    // Left click on the date opens the calendar sheet.
    signal dateClicked()

    // Horizontal center of the date label in the Clock's coordinates, so the
    // floating calendar panel is centered on the date and not on the whole
    // clock.
    readonly property real dateCenterX: row.x + dateLabel.x + dateLabel.width / 2

    implicitHeight: Dimensions.control.height
    // Match the now-playing island's reserved slot so the workspaces pill
    // stays centered (see Dimensions.bar.centerSlot). The time uses tabular
    // figures, so its width no longer changes with every second.
    implicitWidth: Math.max(Dimensions.bar.centerSlot,
        row.implicitWidth + Dimensions.padding.chipHorizontal * 2)

    SystemClock { id: sysClock; precision: SystemClock.Seconds }

    // The clock ticks every second, but the date only changes at midnight. The
    // cheap calendar-day key rides the per-second path; the formatted label is
    // written only when that key changes, so the date text is not re-formatted
    // (and re-laid-out) 60 times a minute for the same result.
    readonly property int dayKey: {
        const d = sysClock.date;
        return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
    }
    property string dateText: Qt.formatDateTime(new Date(), "ddd, dd MMM")

    onDayKeyChanged: root.dateText = Qt.formatDateTime(sysClock.date, "ddd, dd MMM")
    Component.onCompleted: root.dateText = Qt.formatDateTime(sysClock.date, "ddd, dd MMM")

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            id: dateLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateText
            color: dateMouse.containsMouse ? Colors.onSurface : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium

            Behavior on color {
                ColorAnimation {
                    duration: Motion.hover
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }

            // Hover target: a pill larger than the label so the date reads as
            // a control without widening the clock row. The child is not
            // clipped (Text does not clip) and the separator is a later
            // sibling, so the pill can never cover the other labels.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -6
                z: -1
                radius: height / 2
                color: Colors.stateLayer(Colors.onSurface, 0.08)
                opacity: dateMouse.containsMouse ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.hover
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Motion.standardDecelerateCurve
                    }
                }
            }

            MouseArea {
                id: dateMouse

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dateClicked()
            }
        }

        // Separator
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            implicitWidth: 1
            height: 12
            radius: 0.5
            color: Colors.withAlpha(Colors.outlineVariant, 0.5)
        }

        // Neon time. Tabular figures keep every digit in the same slot;
        // proportional figures made the label a few pixels narrower or wider
        // every second, shifting the date and layout labels (and the chip
        // itself whenever the content exceeded the reserved slot).
        Text {
            id: timeLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "HH:mm:ss")
            color: Colors.primary
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
            font.features: ({ "tnum": 1 })
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            implicitWidth: 1
            height: 12
            radius: 0.5
            visible: keyboardLayout.layoutCount > 1
            color: Colors.withAlpha(Colors.outlineVariant, 0.5)
        }

        KeyboardLayout {
            id: keyboardLayout
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
