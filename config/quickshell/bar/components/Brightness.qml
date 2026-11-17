import QtQuick
import "../../theme"

// Brightness chip: neon icon, progress accent bar.
Pill {
    id: root

    implicitWidth: 68
    visible: BrightnessService.available

    icon: BrightnessService.value < 34
        ? Icons.brightnessLow
        : BrightnessService.value < 67
            ? Icons.brightnessMedium
            : Icons.brightnessHigh
    iconColor: Colors.primary
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
            if (wheel.angleDelta.y > 0) BrightnessService.adjust(5);
            else if (wheel.angleDelta.y < 0) BrightnessService.adjust(-5);
        }
    }

    // Neon progress bar
    Rectangle {
        x: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: (parent.width - 12) * BrightnessService.value / 100
        height: 2
        radius: 1
        color: Colors.withAlpha(Colors.primary, 0.75)
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
}
