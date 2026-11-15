import QtQuick
import "../../theme"

// Volume chip: neon icon, mute = red, progress accent bar.
Pill {
    id: root

    implicitWidth: 64
    icon: AudioService.muted ? Icons.volumeOff : Icons.volumeUp
    iconColor: AudioService.muted ? Colors.error : Colors.primary
    text: AudioService.volume + "%"
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AudioService.toggleMute()
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) AudioService.volumeUp();
            else if (wheel.angleDelta.y < 0) AudioService.volumeDown();
        }
    }

    // Neon progress bar
    Rectangle {
        x: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: (parent.width - 12) * Math.min(AudioService.volume, 100) / 100
        height: 2
        radius: 1
        color: AudioService.muted
            ? Colors.withAlpha(Colors.error, 0.6)
            : Colors.withAlpha(Colors.primary, 0.75)
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
    }
}
