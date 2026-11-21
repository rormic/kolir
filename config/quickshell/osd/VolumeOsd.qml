import QtQuick
import Quickshell
import "../theme"
import "../services"

Scope {
    Connections {
        target: AudioService
        function onVolumeChangedManually(vol, isMuted) {
            osd.show();
        }
    }

    OsdPanel {
        id: osd

        layerNamespace: "volume-osd"

        icon: AudioService.muted
            ? Icons.volumeOff
            : (AudioService.volume === 0
                ? Icons.volumeMute
                : (AudioService.volume < 50 ? Icons.volumeDown : Icons.volumeUp))
        iconColor: AudioService.muted ? Colors.error : Colors.primary

        value: AudioService.volume
        indicatorColor: AudioService.muted
            ? Colors.withAlpha(Colors.error, 0.85)
            : Colors.primary

        borderColor: AudioService.muted
            ? Colors.withAlpha(Colors.error, 0.5)
            : Colors.withAlpha(Colors.primary, 0.45)
        glowColor: AudioService.muted
            ? Colors.withAlpha(Colors.error, 0.7)
            : Colors.withAlpha(Colors.primary, 0.7)

        text: AudioService.muted ? "Mute" : (AudioService.volume + "%")
        textColor: AudioService.muted ? Colors.error : Colors.onSurface
    }
}
