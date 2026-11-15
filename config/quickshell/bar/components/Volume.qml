import QtQuick
import "../../theme"

// Volume chip: click to mute, scroll to adjust.
Pill {
    id: root

    implicitWidth: 64
    icon: AudioService.muted ? Icons.volumeOff : Icons.volumeUp
    iconColor: AudioService.muted ? Colors.error : Colors.onSurfaceVariant
    text: AudioService.volume + "%"
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: AudioService.muted ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
    spacing: 4

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: AudioService.toggleMute()

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                AudioService.volumeUp();
            else if (wheel.angleDelta.y < 0)
                AudioService.volumeDown();
        }
    }
}
