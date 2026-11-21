import QtQuick
import "../../services"
import "../../theme"

// Bar indicator for CaffeineService. It only takes space while the session is
// being kept awake; timed sessions also show the remaining time. Clicking it
// opens settings, where the switch and the duration presets live.
Pill {
    id: root

    signal activated()

    visible: CaffeineService.enabled
    icon: Icons.caffeine
    iconColor: Colors.primary
    text: CaffeineService.timed ? CaffeineService.shortLabel : ""
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
    active: true

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
