import QtQuick
import Quickshell
import "../../theme"

// Clock chip: date dim + neon time + keyboard layout.
Surface {
    id: root

    implicitHeight: Dimensions.control.height
    // Proportional digits make the time 2-4 px narrower or wider every second.
    // Reserving a stable minimum keeps the chip from pulsing and gives the
    // now-playing island an exact mirror width (see Dimensions.bar.centerSlot).
    implicitWidth: Math.max(Dimensions.bar.centerSlot,
        row.implicitWidth + Dimensions.padding.chipHorizontal * 2)
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    SystemClock { id: sysClock; precision: SystemClock.Seconds }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            id: dateLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "ddd, dd MMM")
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
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

        // Neon time
        Text {
            id: timeLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "HH:mm:ss")
            color: Colors.primary
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            implicitWidth: 1
            height: 12
            radius: 0.5
            color: Colors.withAlpha(Colors.outlineVariant, 0.5)
        }

        KeyboardLayout { anchors.verticalCenter: parent.verticalCenter }
    }
}
