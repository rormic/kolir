import QtQuick
import "../../services"
import "../../theme"

// Caffeine status: a flat readout, not a control.
//
// It only takes space while the session is being kept awake; timed sessions
// also show the remaining time. The switch and the duration presets live in
// Settings, so this item is deliberately not clickable.
StatusItem {
    id: root

    visible: CaffeineService.enabled
    icon: Icons.caffeine
    iconColor: Colors.primary
    text: CaffeineService.timed ? CaffeineService.shortLabel : ""
    textColor: Colors.onSurfaceVariant
}
