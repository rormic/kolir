import QtQuick
import "../../services"
import "../../theme"

// Battery chip: level icon plus percentage, with a bolt while charging.
//
// The chip only takes space where a battery belongs. Desktops have no
// UPower battery and a non-portable chassis, so it stays hidden; a laptop with
// no usable pack still shows the alert glyph and turns the icon red, so a
// missing, dead or not-yet-reported battery never fails silently.
Pill {
    id: root

    visible: BatteryService.expected

    function chargeIcon(percent, charging) {
        if (charging) {
            if (percent >= 90)
                return Icons.batteryChargingFull;
            if (percent >= 80)
                return Icons.batteryCharging80;
            if (percent >= 60)
                return Icons.batteryCharging60;
            if (percent >= 50)
                return Icons.batteryCharging50;
            if (percent >= 30)
                return Icons.batteryCharging30;
            return Icons.batteryCharging20;
        }

        if (percent >= 95)
            return Icons.batteryFull;
        if (percent >= 80)
            return Icons.battery6Bar;
        if (percent >= 60)
            return Icons.battery5Bar;
        if (percent >= 45)
            return Icons.battery4Bar;
        if (percent >= 30)
            return Icons.battery3Bar;
        if (percent >= 15)
            return Icons.battery2Bar;
        if (percent >= 5)
            return Icons.battery1Bar;
        return Icons.battery0Bar;
    }

    icon: BatteryService.present
        ? root.chargeIcon(BatteryService.percentage, BatteryService.charging)
        : Icons.batteryMissing
    iconColor: !BatteryService.present || BatteryService.low
        ? Colors.error
        : BatteryService.charging
            ? Colors.primary
            : Colors.onSurfaceVariant
    text: BatteryService.present ? BatteryService.percentage + "%" : ""
    textSize: Typography.size.labelMedium
    textColor: BatteryService.low ? Colors.error : Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
}
