import QtQuick
import "../../services"
import "../../theme"

// Headset battery chip: headphones glyph plus the live percentage.
//
// The chip only exists while a connected audio device actually reports a
// battery, so desktops and sessions without a headset keep the bar unchanged.
// A charging headset tints the glyph primary; 15% or less turns the label red,
// matching the laptop battery chip.
//
// When the helper could not re-read the headset and fell back to an older
// sample, a small clock marks the value as cached: the percentage is still the
// last known level, not a live measurement.
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
    textColor: DeviceBatteryService.low
        ? Colors.error
        : DeviceBatteryService.stale
            ? Colors.onSurfaceVariant
            : Colors.onSurface
    trailingIcon: DeviceBatteryService.stale ? Icons.schedule : ""
    trailingIconColor: Colors.onSurfaceVariant
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
}
