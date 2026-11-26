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

    // Playback evidence, independent of the optimistic toggle state.
    //
    // Firefox/Zen keep PlaybackStatus "Playing" after a stream or video is
    // paused: their media element flips Rate to 0 instead, and the stale status
    // would otherwise keep the pause glyph and the progress timer alive
    // forever. Rate defaults to 1 when a player omits it, so a player without
    // MPRIS Rate support is unaffected.
    readonly property bool statusPlaying: root.player !== null
        && root.player.playbackState === MprisPlaybackState.Playing
    readonly property real playbackRate: {
        if (!root.player || typeof root.player.rate !== "number" || !isFinite(root.player.rate))
            return 1;
        return root.player.rate;
    }
    readonly property bool evidencePlaying: root.statusPlaying && root.playbackRate > 0
    readonly property bool evidencePaused: root.player !== null
        && (root.player.playbackState === MprisPlaybackState.Stopped
            || (root.statusPlaying && root.playbackRate <= 0))

    // Fallback for players that report neither a state nor a rate after a
    // toggle. Clear evidence always wins, so a stale status cannot resurrect
    // playback after an external pause.
    property bool assumedPlaying: false
    readonly property bool reallyPlaying: root.evidencePlaying
        ? true
        : (root.evidencePaused ? false : root.assumedPlaying)

    function playerPlaysNow(p) {
        if (!p || p.playbackState !== MprisPlaybackState.Playing)
            return false;
        const rate = (typeof p.rate === "number" && isFinite(p.rate)) ? p.rate : 1;
        return rate > 0;
    }

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

            // Only real playback refreshes the activity tick. A browser that
            // leaves PlaybackStatus "Playing" on pause must not stay the
            // "most recently active" player forever, or another paused player
            // could never be shown.
            if (playerPlaysNow(p) || advancing)
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

        // Keep a player that is genuinely playing so two active players do not
        // make the island flip on every poll. A stale "Playing" (a paused
        // browser stream) does not count as playing here.
        let next = null;
        if (root.player && list.includes(root.player) && playerPlaysNow(root.player))
            next = root.player;
        else
            next = list.find(p => playerPlaysNow(p) && !String(p.dbusName).endsWith(".playerctld"))
                ?? list.find(p => playerPlaysNow(p))
                ?? bestReal ?? bestProxy ?? list[0] ?? null;

        if (next !== root.player)
            root.player = next;
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

    readonly property bool webMedia: /^https?:\/\//i.test(root.trackUrl)

    readonly property string trackCoverUrl: trackArtUrl !== ""
        ? trackArtUrl
        : TrackText.youtubeThumbnail(trackUrl)

    // Quickshell normalizes Position to seconds while mpris:length stays in
    // microseconds, so keep the raw metadata only for the length and read the
    // position from the player.
    readonly property real rawPosition: (player && typeof player.position === "number" && !isNaN(player.position))
        ? player.position
        : 0

    // Raw mpris:length in microseconds, exactly as the player reported it
    // (0 when absent or malformed). Kept separate from rawLength so the
    // "infinite" sentinel can still be recognised.
    readonly property real rawMetadataLength: {
        if (!player || !player.metadata)
            return 0;
        const len = player.metadata["mpris:length"];
        return (typeof len === "number" && isFinite(len) && len > 0) ? len : 0;
    }

    // A broadcast is confirmed only by the "infinite" duration some players
    // report as INT64_MAX microseconds (Twitch in Zen/Firefox). A missing
    // length is not evidence: Zen also drops mpris:length for ordinary
    // YouTube videos, and Quickshell's player.length mirrors position when
    // lengthSupported is false, so that branch is guarded separately.
    readonly property bool infiniteLength: root.rawMetadataLength >= 9.0e15
        || (player !== null && player.lengthSupported
            && typeof player.length === "number" && isFinite(player.length)
            && player.length >= 9.0e12)

    readonly property real rawLength: {
        if (root.infiniteLength)
            return 0;
        const len = root.rawMetadataLength;
        // Firefox/Zen report a live stream's uptime as the duration (the Lofi
        // Girl radio reported ~14 hours). No normal web video exceeds
        // YouTube's 12 hour upload cap, so anything longer is not a usable
        // length. Treat it as unknown; this alone must not raise the LIVE
        // badge.
        if ((root.webMedia || root.trackUrl === "") && len > 12 * 3600 * 1000000)
            return 0;
        return len;
    }

    // A real duration from the player for the current track. This is the
    // frozen-position marker's off switch: a markerless live stream has no
    // length at all, while a normal video reports one (or restores it after
    // a metadata gap). A web duration above 12 h is an uptime, not a usable
    // length, so it must not veto the frozen-position marker either.
    readonly property bool hasLength: root.rawLength > 0
        || (player !== null && player.lengthSupported && !root.infiniteLength
            && typeof player.length === "number" && isFinite(player.length)
            && player.length > 0
            && player.length <= 12 * 3600)

    // Position and length in seconds for display
    readonly property real position: rawPosition

    // Firefox/YouTube briefly drop mpris:length while seeking or changing
    // tracks. Remembering the last positive duration for the current track
    // keeps the island from flipping to "live" mid-gesture.
    property real stickyLength: 0

    // Durations seen for a media URL during this shell session. Firefox/Zen
    // also drop mpris:length for a normal video in a background tab, and the
    // player can re-select that track after another tab held the media
    // session; without this cache the same video would be re-detected as a
    // broadcast from an absence. A URL that never reports a duration (a real
    // live stream) never enters the cache.
    property var knownLengths: ({})

    readonly property string lengthKey: trackUrl !== ""
        ? trackUrl
        : (player ? player.dbusName + "/" + (player.trackTitle || "") : "")

    // A live broadcast. Two confirmed markers raise it: an "infinite"
    // mpris:length (INT64_MAX microseconds, which Twitch reports in
    // Zen/Firefox), or a raw MPRIS Position frozen at the live edge with no
    // usable duration (a YouTube live in Zen). A missing duration alone is
    // still not evidence: Zen also drops mpris:length for ordinary videos.
    property bool live: false

    // True when `live` came from the frozen-position marker rather than the
    // sentinel. Only this path is cleared by a moving position or a restored
    // duration; a sentinel broadcast keeps its badge.
    property bool frozenLive: false
    property bool sawLengthForTrack: false
    property real frozenSince: -1
    property real frozenAnchorPosition: -1
    readonly property real frozenMovementLimit: 1
    // Zen reports a stream pinned at the live edge as Position 0, whatever the
    // stream's elapsed uptime is. A frozen value anywhere else is not the live
    // edge: an ordinary video's raw Position also stops moving while its tab is
    // in the background (or when the browser caches the sample), and latching on
    // any frozen value made such a video turn LIVE after a few minutes.
    readonly property real frozenLiveEdgeLimit: 1
    readonly property bool rawPositionAtLiveEdge: root.rawMprisPosition >= 0
        && root.rawMprisPosition < root.frozenLiveEdgeLimit
    readonly property int frozenConfirmMs: 10000

    // Quickshell extrapolates player.position from the last D-Bus sample
    // (last position + elapsed * rate), so a markerless live whose Position
    // stays at the live edge still looks like it advances. The frozen marker
    // must read the raw MPRIS Position; this is sampled over D-Bus only while
    // a stream has no usable duration (one query per second).
    property real rawMprisPosition: -1
    property int rawPositionGeneration: 0
    property int rawPositionQueryGeneration: -1
    readonly property bool frozenProbeWanted: root.pollActive && root.hasPlayer
        && (root.frozenLive || root.reallyPlaying)
        && !root.infiniteLength && !root.hasLength
        && !root.sawLengthForTrack
        && root.player !== null && root.player.positionSupported

    readonly property string currentTrackKey: player
        ? player.dbusName + "/" + String(player.uniqueId) + "/" + (player.trackTitle || "")
        : ""

    readonly property real length: (root.live || root.infiniteLength) ? 0 : root.stickyLength

    onCurrentTrackKeyChanged: {
        root.live = false;
        root.frozenLive = false;
        root.resetRawPosition();
        root.stickyLength = 0;
        const cached = root.knownLengths[root.lengthKey];
        if (typeof cached === "number" && cached > 0)
            root.stickyLength = cached;
        else if (root.rawLength > 0)
            root.stickyLength = root.rawLength / 1000000;
        // Only a duration actually seen for this track may veto the frozen
        // marker. A cached duration for the same URL can belong to a pre-roll
        // ad, so it is intentionally not used here.
        root.sawLengthForTrack = root.hasLength;
    }

    // The URL can arrive after the duration. Move a length that was cached
    // under the fallback key onto the URL key, and restore a cached URL length
    // when the metadata finally identifies the media.
    onLengthKeyChanged: {
        // A new URL is a new media: the 10 s frozen-position window starts
        // over, and a badge that came from that window must not leak across.
        root.resetRawPosition();
        clearFrozenLive();
        if (root.lengthKey === "")
            return;
        const cached = root.knownLengths[root.lengthKey];
        if (typeof cached === "number" && cached > 0) {
            if (root.stickyLength <= 0)
                root.stickyLength = cached;
        } else if (root.rawLength > 0) {
            if (root.lengthKey !== "")
                root.knownLengths[root.lengthKey] = root.rawLength / 1000000;
        }
    }

    onRawLengthChanged: {
        if (root.rawLength > 0) {
            clearFrozenLive();
            root.sawLengthForTrack = true;
            root.stickyLength = root.rawLength / 1000000;
            if (root.lengthKey !== "")
                root.knownLengths[root.lengthKey] = root.stickyLength;
            checkPausedLength();
        }
    }

    // A duration that appears through the normalized player property (without
    // a metadata length) also ends the frozen-position badge immediately.
    onHasLengthChanged: {
        if (root.hasLength) {
            root.sawLengthForTrack = true;
            clearFrozenLive();
        }
    }

    // A URL change resets the frozen-position timer even when the track key
    // did not change (some players update the URL without the title).
    onTrackUrlChanged: {
        root.resetRawPosition();
        clearFrozenLive();
    }

    // A paused broadcast can re-report a real (uptime) duration after the
    // sentinel disappears. If that duration has meaningful remaining time,
    // the track is a VOD and the badge is wrong. A broadcast's stale duration
    // is its uptime, so it is close to the last position (or the position is
    // 0); a VOD has real remaining time. Clear the flag only when the
    // remaining time is meaningful, so a paused live stream stays live.
    readonly property real liveRemainingThreshold: 30

    function checkPausedLength() {
        if (!root.live || root.reallyPlaying || root.rawLength <= 0)
            return;
        // Position is not reactive; ask Quickshell for a fresh value before
        // the timer compares it with the just-restored duration.
        if (root.player && root.player.positionChanged)
            root.player.positionChanged();
        pausedLengthProbe.restart();
    }

    Timer {
        id: pausedLengthProbe

        interval: 500
        repeat: false
        onTriggered: {
            if (!root.live || root.reallyPlaying || root.rawLength <= 0)
                return;
            if (root.rawPosition > 0
                    && root.stickyLength - root.rawPosition > root.liveRemainingThreshold) {
                root.live = false;
                root.frozenLive = false;
                root.frozenSince = -1;
            }
        }
    }

    function clearFrozenLive() {
        if (!root.frozenLive)
            return;
        root.live = false;
        root.frozenLive = false;
        root.frozenSince = -1;
    }

    function resetRawPosition() {
        root.rawMprisPosition = -1;
        root.rawPositionGeneration++;
        root.rawPositionQueryGeneration = -1;
        root.frozenSince = -1;
        root.frozenAnchorPosition = -1;
    }

    // Markerless YouTube live: the player exposes a normal track with no
    // duration and a raw MPRIS Position pinned at the live edge (Zen reports
    // 0). Quickshell's player.position cannot be used here because it
    // extrapolates from the last D-Bus sample. A normal video reports its own
    // playback position, which is not the live edge even when the raw sample
    // stops updating in a background tab; a duration that appears cancels the
    // probe too. This path is deliberately separate from the sentinel so
    // Twitch's broadcast badge is never cleared here.
    function sampleFrozenLive() {
        if (root.rawMprisPosition < 0) {
            if (!root.frozenLive)
                root.frozenSince = -1;
            return;
        }
        const moved = root.frozenAnchorPosition >= 0
            && Math.abs(root.rawMprisPosition - root.frozenAnchorPosition)
                >= root.frozenMovementLimit;
        // Keep the anchor while the frozen badge is visible, so a later
        // position movement can clear it. The raw probe keeps sampling while
        // frozenLive is true for exactly this reason.
        if (root.frozenLive) {
            if (moved || root.hasLength || root.sawLengthForTrack
                    || !root.rawPositionAtLiveEdge) {
                clearFrozenLive();
                root.frozenSince = -1;
                root.frozenAnchorPosition = -1;
            }
            return;
        }
        if (!root.pollActive || !root.hasPlayer || !root.reallyPlaying
                || root.playbackRate <= 0 || root.infiniteLength
                || root.hasLength || root.sawLengthForTrack || root.live) {
            root.frozenSince = -1;
            root.frozenAnchorPosition = -1;
            return;
        }
        if (moved || !root.rawPositionAtLiveEdge) {
            // The position is moving, or it is frozen somewhere in the middle
            // of a media timeline (an ordinary video in a background tab):
            // start the 10 s window over at the next live-edge sample.
            root.frozenSince = -1;
            root.frozenAnchorPosition = -1;
            return;
        }
        if (root.frozenSince < 0) {
            root.frozenSince = Date.now();
            root.frozenAnchorPosition = root.rawMprisPosition;
            return;
        }
        if (Date.now() - root.frozenSince >= root.frozenConfirmMs) {
            root.frozenLive = true;
            root.live = true;
        }
    }

    readonly property bool progressSupported: player !== null
        && !root.live
        && length > 0
        && (player.canSeek ?? true)

    // 0..1 position in the current track
    readonly property real progress: (length > 0)
        ? Math.max(0, Math.min(1, position / length))
        : 0

    // Live probe: only the explicit "infinite" duration may raise the badge.
    // An unknown or temporarily missing length must not: Zen/YouTube drop
    // mpris:length for ordinary videos, and a fresh shell may not have seen
    // the real duration yet. The 2 s delay only debounces metadata blips.
    Timer {
        id: liveProbe

        interval: 2000
        repeat: false
        running: root.pollActive && root.hasPlayer && root.reallyPlaying
            && !root.live && root.infiniteLength
        onTriggered: {
            if (root.pollActive && root.hasPlayer && root.reallyPlaying
                    && root.infiniteLength) {
                root.frozenLive = false;
                root.frozenSince = -1;
                root.live = true;
            }
        }
    }

    // A real duration that stays present during playback means this is a
    // normal track after all (some players publish metadata late). A paused
    // live stream also publishes its stale duration, but it is not playing
    // then, so the live flag survives a pause.
    Timer {
        id: lengthRestoreProbe

        interval: 1500
        repeat: false
        running: root.live && root.reallyPlaying && root.rawLength > 0
        onTriggered: {
            if (root.reallyPlaying && root.rawLength > 0) {
                root.live = false;
                root.frozenLive = false;
                root.frozenSince = -1;
            }
        }
    }

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
        // A live broadcast has no meaningful absolute position (Firefox even
        // reports 0 while playing and a stale value on pause), so never seek.
        if (!player || !player.canSeek || root.live)
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
        if (!player || root.live || length <= 0)
            return;
        seekTo(ratio * length);
    }

    // Optimistic playback state. Some players (Firefox/Zen) never update
    // PlaybackStatus, and quickshell's togglePlaying() then keeps sending
    // Pause and can never resume. The flag is only a fallback when the player
    // reports neither state nor Rate; the evidence above always wins.
    function togglePlaying() {
        if (!interactive || !player)
            return;

        // Act on what the island shows, not on a possibly stale flag: after an
        // external pause the old code would keep sending Pause.
        const playing = root.reallyPlaying;
        const action = playing ? "Pause" : "Play";
        assumedPlaying = !playing;

        controlProc.command = [
            "busctl", "--user", "call", player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            action
        ];
        controlProc.running = true;
    }

    function syncAssumedState() {
        if (!player) {
            assumedPlaying = false;
            return;
        }
        if (root.evidencePlaying)
            assumedPlaying = true;
        else if (root.evidencePaused)
            assumedPlaying = false;
        else
            assumedPlaying = root.statusPlaying;
    }

    function nextTrack() {
        if (player && player.canGoNext)
            player.next();
    }

    function prevTrack() {
        if (player && player.canGoPrevious)
            player.previous();
    }

    // A pause can arrive before the restored duration, or after it; check in
    // both orders so a false live flag from a background-tab gap is cleared.
    // A pause also breaks the continuous 10 s frozen-position window.
    onReallyPlayingChanged: {
        checkPausedLength();
        if (!root.reallyPlaying)
            root.frozenSince = -1;
    }

    // The track key includes the player's bus name, so a selection change
    // already resets the length and live flag through
    // onCurrentTrackKeyChanged. Do not clear stickyLength here: this handler
    // may run after that one and would wipe a length the new player has
    // already reported, making the live probe see an unknown duration.
    onPlayerChanged: {
        root.frozenLive = false;
        root.resetRawPosition();
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
            root.sampleFrozenLive();
        }
    }

    // Raw MPRIS Position for the frozen-position marker. Quickshell's
    // player.position is extrapolated, so a live edge pinned at a constant
    // position would otherwise look like it advances. The probe runs only
    // while a stream has no usable duration; normal videos with a length never
    // spawn it.
    Process {
        id: rawPositionProbe

        running: false

        command: root.player ? [
            "busctl", "--user", "get-property",
            root.player.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "Position"
        ] : []

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.rawPositionQueryGeneration !== root.rawPositionGeneration)
                    return;
                const match = /^\s*x\s+(-?\d+)/.exec(text);
                if (!match) {
                    // An unreadable answer must not leave the previous sample
                    // in place: a constant stale value looked exactly like a
                    // frozen live edge and raised a false LIVE on a normal
                    // video.
                    root.rawMprisPosition = -1;
                    root.frozenSince = -1;
                    root.frozenAnchorPosition = -1;
                    return;
                }
                root.rawMprisPosition = Number(match[1]) / 1000000;
                root.sampleFrozenLive();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.frozenProbeWanted
        triggeredOnStart: true

        onTriggered: {
            if (!rawPositionProbe.running && root.player) {
                root.rawPositionQueryGeneration = root.rawPositionGeneration;
                rawPositionProbe.running = true;
            }
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
