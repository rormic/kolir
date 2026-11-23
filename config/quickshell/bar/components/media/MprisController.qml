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

    // Mpris.players is an unnotified model, so a binding over `.values` would
    // evaluate only once. Keep `player` as a plain property and refresh it from
    // a timer while the island is visible.
    property var player: null

    // Selection prefers whatever looks like it is playing right now and falls
    // back to the most recently active player of this session (no persistence).
    // PlaybackStatus alone is not enough: Firefox/YouTube often leave it stale,
    // so a moving position counts as playback too. Position readings need the
    // monitoring signal to be emitted for every player we inspect.
    property int activityTick: 0
    property var lastActiveTicks: ({})
    property var positionSamples: ({})
    // True while the selected player looks like it is really playing (status
    // or moving position), independent of the optimistic toggle state.
    property bool activeSelected: false
    readonly property bool reallyPlaying: root.assumedPlaying || root.activeSelected

    function pickPlayer() {
        const list = Mpris.players.values;
        const tick = root.activityTick + 1;
        root.activityTick = tick;

        for (const p of list) {
            const key = String(p.dbusName);
            const pos = (typeof p.position === "number" && isFinite(p.position)) ? p.position : 0;
            const prev = root.positionSamples[key];
            const advancing = prev !== undefined && pos > prev + 0.05 && pos < prev + 60;
            root.positionSamples[key] = pos;

            if (p.isPlaying || advancing)
                root.lastActiveTicks[key] = tick;

            // Refresh the cached position for the next sample (Quickshell only
            // monitors positions that ask for it).
            if (p.positionChanged)
                p.positionChanged();
        }

        let bestReal = null;
        let bestRealTick = -1;
        let bestProxy = null;
        let bestProxyTick = -1;
        for (const p of list) {
            const t = root.lastActiveTicks[String(p.dbusName)];
            if (t === undefined)
                continue;
            // playerctld only mirrors another player and can carry stale
            // metadata, so prefer the real bus when both look equally active.
            if (String(p.dbusName).endsWith(".playerctld")) {
                if (t > bestProxyTick) {
                    bestProxyTick = t;
                    bestProxy = p;
                }
            } else if (t > bestRealTick) {
                bestRealTick = t;
                bestReal = p;
            }
        }

        const next = bestReal ?? bestProxy ?? list[0] ?? null;

        if (next !== root.player)
            root.player = next;

        // A player whose position is moving counts as playing even when its
        // PlaybackStatus lies (Firefox/YouTube); this only feeds the icon and
        // the progress polling, never the optimistic control state.
        root.activeSelected = !!next
            && (next.isPlaying || root.lastActiveTicks[String(next.dbusName)] === tick);
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

    // Firefox/YouTube briefly drop mpris:length while seeking or changing
    // tracks. Remembering the last positive duration for the current track
    // keeps the island from flipping to "live" mid-gesture.
    property real stickyLength: 0
    readonly property string currentTrackKey: player
        ? player.dbusName + "/" + String(player.uniqueId) + "/" + (player.trackTitle || "")
        : ""

    readonly property real length: root.stickyLength

    onCurrentTrackKeyChanged: {
        root.stickyLength = 0;
        if (root.rawLength > 0)
            root.stickyLength = root.rawLength / 1000000;
    }

    onRawLengthChanged: {
        if (root.rawLength > 0)
            root.stickyLength = root.rawLength / 1000000;
    }

    readonly property bool progressSupported: player !== null
        && length > 0
        && (player.canSeek ?? true)

    // 0..1 position in the current track
    readonly property real progress: (length > 0)
        ? Math.max(0, Math.min(1, position / length))
        : 0

    // Fallback D-Bus transport for players without Quickshell seek support.
    Process {
        id: seekProc

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("NowPlaying: MPRIS seek error:", text.trim());
            }
        }

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("NowPlaying: MPRIS seek failed, exit code", code);
            if (root.player)
                root.player.positionChanged();
        }
    }

    // Absolute MPRIS seek via D-Bus SetPosition. Some players (Firefox/YouTube)
    // do not implement the relative Seek method at all and only honour
    // SetPosition, which also matches their own notion of the current track id.
    function seekTo(seconds) {
        if (!player || !player.canSeek)
            return;

        const maxSecs = length > 0 ? length : 0;
        const targetSecs = maxSecs > 0 ? Math.max(0, Math.min(maxSecs, seconds)) : Math.max(0, seconds);

        if (!player.dbusName) {
            // Last resort without a bus name: relative offset through Quickshell.
            if (typeof player.seek === "function")
                player.seek(targetSecs - position);
            return;
        }

        const microSecs = Math.round(targetSecs * 1000000);

        // Quickshell exposes mpris:trackid as a QVariant(QDBusObjectPath) whose
        // debug form is not an object path, so recover the real path when Qt's
        // wrapper format matches and otherwise fall back to the conventional
        // "no track" id (players that honour SetPosition accept it).
        const rawTid = player.metadata ? player.metadata["mpris:trackid"] : undefined;
        let trackId = "";
        if (rawTid && typeof rawTid === "object" && typeof rawTid.path === "string")
            trackId = rawTid.path;
        else if (typeof rawTid === "string")
            trackId = rawTid;
        else {
            const match = String(rawTid).match(/QDBusObjectPath\("([^"]+)"\)/);
            if (match)
                trackId = match[1];
        }
        if (!trackId.startsWith("/"))
            trackId = "/org/mpris/MediaPlayer2/TrackList/NoTrack";

        seekProc.command = [
            "busctl", "--user", "call", player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "SetPosition",
            "ox", trackId, String(microSecs)
        ];
        seekProc.running = true;

        if (player.positionChanged)
            player.positionChanged();
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

    onPlayerChanged: {
        root.stickyLength = 0;
        syncAssumedState();
    }

    // Player selection has to be polled: the Mpris players model carries no
    // change notification.
    Timer {
        interval: 500
        running: root.pollActive
        repeat: true
        triggeredOnStart: true

        onTriggered: root.pickPlayer()
    }

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
        running: root.pollActive && root.hasPlayer && root.reallyPlaying
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
        root.pickPlayer();
        syncAssumedState();
    }
}
