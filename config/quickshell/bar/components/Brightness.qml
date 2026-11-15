import QtQuick
import "../../theme"

// Brightness chip: scroll to adjust the external display backlight (DDC/CI).
Pill {
    id: root

    implicitWidth: 68
    visible: BrightnessService.available

    icon: BrightnessService.value < 34
        ? Icons.brightnessLow
        : BrightnessService.value < 67
            ? Icons.brightnessMedium
            : Icons.brightnessHigh
    iconColor: Colors.onSurfaceVariant
    text: BrightnessService.value + "%"
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                BrightnessService.adjust(5);
            else if (wheel.angleDelta.y < 0)
                BrightnessService.adjust(-5);
        }
    }
}
