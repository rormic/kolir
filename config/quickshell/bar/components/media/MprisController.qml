import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// MPRIS state and control for the now-playing island: player selection,
// optimistic playback state with raw D-Bus control, favicon lookup, progress
// polling and the nowPlaying IPC. The view only renders this state.
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
    readonly property string trackText: player
        ? ((player.trackArtist ? player.trackArtist + " – " : "") + (player.trackTitle || ""))
        : ""

    readonly property bool progressSupported: player !== null
        && player.lengthSupported
        && player.positionSupported
        && player.length > 0

    // 0..1 position in the current track. `position` does not update
    // reactively; the poll Timer below emits its change signal while
    // playing so this binding re-reads the fresh value.
    readonly property real progress: progressSupported && player
        ? Math.max(0, Math.min(1, player.position / player.length))
        : 0

    // Browsers expose the current tab URL as xesam:url, so use its host to
    // look up a local favicon.
    readonly property string trackUrl: {
        if (!player || !player.metadata)
            return "";
        const url = player.metadata["xesam:url"];
        return typeof url === "string" ? url : "";
    }

    readonly property string siteHost: {
        const match = trackUrl.match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i);
        return match ? match[1].toLowerCase() : "";
    }

    property string siteIconPath: ""
    property string faviconRequestHost: ""

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

    function refreshSiteIcon() {
        siteIconPath = "";

        if (!hasPlayer || trackUrl === "" || siteHost === "")
            return;

        faviconRequestHost = siteHost;
        faviconProc.running = false;
        faviconProc.running = true;
    }

    function clearSiteIcon() {
        siteIconPath = "";
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

    // The host is enough to identify the favicon, so switching tracks on the
    // same site does not touch the browser database again.
    onSiteHostChanged: refreshSiteIcon()

    // Retry when a track changes on the same host but the first lookup found
    // nothing (for example a site whose icon was cached after it was played).
    onTrackUrlChanged: {
        if (siteHost !== "" && siteIconPath === "" && !faviconProc.running)
            refreshSiteIcon();
    }

    IpcHandler {
        target: "nowPlaying"

        function playPause(): void {
            root.togglePlaying();
        }

        function next(): void {
            root.nextTrack();
        }

        function previous(): void {
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

    // Local site favicon lookup. The helper reads the browser's
    // favicons.sqlite and caches the extracted image; no network is used.
    Process {
        id: faviconProc

        running: false
        command: [
            "python3",
            Quickshell.shellPath("scripts/favicon.py"),
            Quickshell.cachePath("favicons"),
            root.trackUrl
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();

                // Ignore a late result from a previous site.
                if (path !== "" && root.faviconRequestHost === root.siteHost)
                    root.siteIconPath = path;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("NowPlaying: favicon lookup:", text.trim());
            }
        }

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("NowPlaying: favicon helper exited with code", code);
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
        refreshSiteIcon();
    }
}
