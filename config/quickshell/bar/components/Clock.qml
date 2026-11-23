import QtQuick
import Quickshell
import "../../theme"

// Clock chip: date dim + neon time + keyboard layout.
Surface {
    id: root

    implicitHeight: Dimensions.control.height
    // Match the now-playing island's reserved slot so the workspaces pill
    // stays centered (see Dimensions.bar.centerSlot). The time uses tabular
    // figures, so its width no longer changes with every second.
    implicitWidth: Math.max(Dimensions.bar.centerSlot,
        row.implicitWidth + Dimensions.padding.chipHorizontal * 2)
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

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
            color: Colors.withAlpha(Colors.outlineVariant, 0.5)
        }

        KeyboardLayout { anchors.verticalCenter: parent.verticalCenter }
    }
}
