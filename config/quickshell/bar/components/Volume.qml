import QtQuick
import "../../theme"
import "../../services"

// Volume chip: neon icon, mute = red, progress accent bar.
Pill {
    id: root

    implicitWidth: 64
    icon: AudioService.muted
        ? Icons.volumeOff
        : (AudioService.volume === 0
            ? Icons.volumeMute
            : (AudioService.volume < 50 ? Icons.volumeDown : Icons.volumeUp))
    iconColor: AudioService.muted ? Colors.error : Colors.primary
    text: AudioService.volume + "%"
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
    active: popup.visible

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                popup.toggle();
            else if (mouse.button === Qt.LeftButton)
                AudioService.toggleMute();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) AudioService.volumeUp();
            else if (wheel.angleDelta.y < 0) AudioService.volumeDown();
        }
    }

    VolumePopup {
        id: popup
        anchorItem: root
    }

    // Material 3 linear progress indicator along the bottom edge.
    ProgressIndicator {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 6
            rightMargin: 6
            bottomMargin: 2
        }
        height: implicitHeight
        value: AudioService.volume
        indicatorColor: AudioService.muted
            ? Colors.withAlpha(Colors.error, 0.85)
            : Colors.primary
        trackColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)
    }
}
