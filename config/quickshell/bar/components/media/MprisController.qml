import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "TrackText.js" as TrackText

// MPRIS state and control for the now-playing island: player selection,
// optimistic playback state with raw D-Bus control, progress polling and the
// nowPlaying IPC. The view only renders this state.
Scope {
    id: root

    // Set by the view: polling runs only while the island is visible.
    property bool pollActive: false

    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool interactive: player !== null && player.canControl

    // Browser players report the tab title, which still contains the tab
    // counter and the site suffix. cleanTitle() keeps only the track name.
    readonly property string trackTitle: player
        ? TrackText.cleanTitle(player.trackTitle || "")
        : ""
    readonly property string trackArtist: player ? (player.trackArtist || "") : ""
    readonly property string trackText: trackTitle === ""
        ? ""
        : (trackArtist !== "" ? trackArtist + " – " + trackTitle : trackTitle)

    // mpris:artUrl as reported by the player. The view shows it directly and
    // CoverPalette derives the island palette from it.
    readonly property string trackArtUrl: player ? (player.trackArtUrl || "") : ""

    // Browsers expose the current tab URL as xesam:url. YouTube usually has no
    // mpris:artUrl, so its thumbnail becomes the cover fallback.
    readonly property string trackUrl: {
        if (!player || !player.metadata)
            return "";
        const url = player.metadata["xesam:url"];
        return typeof url === "string" ? url : "";
    }

    readonly property string trackCoverUrl: trackArtUrl !== ""
        ? trackArtUrl
        : TrackText.youtubeThumbnail(trackUrl)

    // Quickshell normalizes Position to seconds while mpris:length stays in
    // microseconds, so keep the raw metadata only for the length and read the
    // position from the player.
    readonly property real rawPosition: (player && typeof player.position === "number" && !isNaN(player.position))
        ? player.position
        : 0

    readonly property real rawLength: {
        if (!player || !player.metadata)
            return 0;
        const len = player.metadata["mpris:length"];
        return (typeof len === "number" && !isNaN(len) && len > 0) ? len : 0;
    }

    // Position and length in seconds for display
    readonly property real position: rawPosition
    readonly property real length: rawLength / 1000000

    readonly property bool progressSupported: player !== null
        && rawLength > 0
        && (player.canSeek ?? true)

    // 0..1 position in the current track
    readonly property real progress: (length > 0)
        ? Math.max(0, Math.min(1, position / length))
        : 0

    // Raw MPRIS seek via D-Bus SetPosition (position in microseconds)
    Process {
        id: seekProc

        running: false

        onExited: (code, status) => {
            if (root.player)
                root.player.positionChanged();
        }
    }

    function seekTo(seconds) {
        if (!player || !player.dbusName)
            return;

        const maxSecs = length > 0 ? length : 0;
        const targetSecs = maxSecs > 0 ? Math.max(0, Math.min(maxSecs, seconds)) : Math.max(0, seconds);
        const microSecs = Math.round(targetSecs * 1000000);

        const trackId = (player.metadata && player.metadata["mpris:trackid"])
            ? String(player.metadata["mpris:trackid"])
            : "/org/mpris/MediaPlayer2/TrackList/NoTrack";

        seekProc.command = [
            "busctl", "--user", "call", player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "SetPosition",
            "ox", trackId, String(microSecs)
        ];
        seekProc.running = true;
    }

    function seekToPercent(ratio) {
        if (!player || length <= 0)
            return;
        seekTo(ratio * length);
    }

    // Optimistic playback state. Some players (Firefox/Zen) never update
    // PlaybackStatus, and quickshell's togglePlaying() then keeps sending
    // Pause and can never resume. We flip this flag ourselves, send raw
    // MPRIS Play/Pause, and resync whenever the player reports a real
    // state change.
    property bool assumedPlaying: false

    function togglePlaying() {
        if (!interactive || !player)
            return;

        const action = assumedPlaying ? "Pause" : "Play";
        assumedPlaying = !assumedPlaying;

        controlProc.command = [
            "busctl", "--user", "call", player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            action
        ];
        controlProc.running = true;
    }

    function syncAssumedState() {
        assumedPlaying = player ? player.isPlaying : false;
    }

    function nextTrack() {
        if (player && player.canGoNext)
            player.next();
    }

    function prevTrack() {
        if (player && player.canGoPrevious)
            player.previous();
    }

    onPlayerChanged: syncAssumedState()

    IpcHandler {
        target: "nowPlaying"

        function playPause() {
            root.togglePlaying();
        }

        function next() {
            root.nextTrack();
        }

        function previous() {
            root.prevTrack();
        }
    }

    // `position` does not update reactively, so emit its change signal once
    // per second while playing (the pattern recommended by the Quickshell
    // MprisPlayer docs).
    Timer {
        running: root.pollActive && root.hasPlayer && root.assumedPlaying
        interval: 1000
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            if (root.player)
                root.player.positionChanged();
        }
    }

    // Raw MPRIS control. quickshell's play()/pause() short-circuit when the
    // reported state already matches, which never happens for players that
    // lie about PlaybackStatus, so the D-Bus methods are called directly.
    Process {
        id: controlProc

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("NowPlaying: MPRIS control error:", text.trim());
            }
        }

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("NowPlaying: MPRIS control call failed, exit code", code);
        }
    }

    // Follow real playback state changes from well-behaved players.
    Connections {
        target: root.player

        function onPlaybackStateChanged() {
            root.syncAssumedState();
        }
    }

    Component.onCompleted: {
        syncAssumedState();
    }
}
