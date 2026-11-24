import QtQuick
import "../../theme"
import "../../services"

// Volume chip: neon icon, mute = red, progress accent bar. The sound sheet is
// owned by Bar (it lives in the bar surface), so the chip only reports left
// clicks through `activated`. While that sheet is open the chip stretches over
// its width and becomes its header (see HeaderPill).
HeaderPill {
    id: root

    // The sheet's title block lives here now, so the chip owns its status line.
    readonly property string soundStatus: {
        const out = AudioService.activeSink;
        if (!out || !out.description)
            return "No output device";

        return AudioService.muted ? "Muted · " + out.description : out.description;
    }

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

    progressValue: AudioService.volume
    progressColor: AudioService.muted
        ? Colors.withAlpha(Colors.error, 0.85)
        : Colors.primary

    adjust: step => {
        if (step > 0) AudioService.volumeUp();
        else AudioService.volumeDown();
    }

    headerIcon: AudioService.muted ? Icons.volumeOff : Icons.volumeUp
    headerIconColor: AudioService.muted ? Colors.error : Colors.primary
    headerTitle: "Sound"
    headerStatus: root.soundStatus
    headerStatusColor: AudioService.muted
        ? Colors.error
        : Colors.onSurfaceVariant
}
