import QtQuick
import Quickshell
import "../../theme"

// Clock chip: date dim + neon time + keyboard layout.
Surface {
    id: root

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal * 2
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    SystemClock { id: sysClock; precision: SystemClock.Seconds }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(sysClock.date, "ddd, dd MMM")
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
        }

        // Neon separator
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 10
            radius: 0.5
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.primary, 0.6) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Neon time
        Text {
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
            height: 10
            radius: 0.5
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.outlineVariant, 0.5) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        KeyboardLayout { anchors.verticalCenter: parent.verticalCenter }
    }
}
