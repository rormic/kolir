import "../../theme"
import Quickshell.Services.Mpris
import QtQuick

// Now playing: pulsing neon music icon + track text.
Pill {
    id: root

    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool hasPlayer: player !== null
    readonly property string trackText: player
        ? ((player.trackArtist ? player.trackArtist + " – " : "") + (player.trackTitle || ""))
        : ""

    property bool enabled: true
    visible: enabled && hasPlayer && trackText !== ""

    icon: Icons.musicNote
    iconColor: Colors.primary
    text: root.trackText
    textSize: Typography.size.labelMedium
    textWeight: Typography.weight.bold
    textColor: Colors.onSurface
    textMaxWidth: 150

    SequentialAnimation on iconItem.opacity {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
    }
}
