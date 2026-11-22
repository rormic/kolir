import QtQuick
import "../../services"
import "../../theme"

// Headset battery chip: headphones glyph plus the live percentage.
//
// The chip only exists while a connected audio device actually reports a
// battery, so desktops and sessions without a headset keep the bar unchanged.
// A charging headset tints the glyph primary; 15% or less turns the label red,
// matching the laptop battery chip.
Pill {
    id: root

    visible: DeviceBatteryService.available

    icon: Icons.headphones
    iconColor: DeviceBatteryService.low
        ? Colors.error
        : DeviceBatteryService.charging
            ? Colors.primary
            : Colors.onSurfaceVariant
    text: DeviceBatteryService.available
        ? DeviceBatteryService.percentage + "%"
        : ""
    textSize: Typography.size.labelMedium
    textColor: DeviceBatteryService.low ? Colors.error : Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
}
