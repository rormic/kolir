import QtQuick
import Quickshell
import "../../theme"

// M3 clock chip: date, time and keyboard layout in one tonal pill.
Surface {
    id: root

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal * 2
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    SystemClock {
        id: sysClock
        precision: SystemClock.Seconds
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "ddd, dd MMM")
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.bold
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "HH:mm:ss")
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 12
            color: Colors.outlineVariant
            opacity: 0.55
        }

        KeyboardLayout {
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
