pragma Singleton
import QtQuick
import Quickshell.Io
import "audio/AudioParser.js" as AudioParser

QtObject {
    id: root

    // Legacy / compatibility surface: state of the *default output*.
    // Kept intact for Volume.qml and VolumeOsd.qml.
    property int volume: 0
    property bool muted: false
    property bool ready: false
    signal volumeChangedManually(int vol, bool isMuted)

    // Full device state used by the bar volume popup.
    property string defaultSinkName: ""
    property string defaultSourceName: ""
    property var sinks: []     // { name, description, icon, channels, muted, isDefault }
    property var sources: []   // { name, description, icon, channels, muted, isDefault }
    // Bluetooth cards only: { name, activeProfile, profiles[] }.
    // Profiles are PipeWire card profiles. A2DP codecs are exposed as
    // "a2dp-sink-<codec>" (plus a bare "a2dp-sink" for AAC) and can be
    // switched with pactl set-card-profile.
    property var cards: []

    readonly property var activeSink: root.sinks.find(s => s.isDefault)
    readonly property var activeSource: root.sources.find(s => s.isDefault)

    // How long to coalesce pactl subscribe bursts before refreshing.
    property Timer debounce: Timer {
        interval: 150
        repeat: false
        onTriggered: root.refresh()
    }

    // Live volume edits are coalesced: the slider reports every pointer move,
    // but pactl only gets the latest value on a short timer. A small queue
    // serializes them with device switches so nothing overlaps.
    property real pendingOutputVolume: -1
    property string pendingOutputSink: ""
    property real pendingInputVolume: -1
    property string pendingInputSource: ""
    // Whether the action now running must be followed by a pactl re-read.
    // Set per queue entry; volume/mute writes clear it (the subscriber
    // reports them), default/route/profile switches set it.
    property bool actionNeedsRefresh: false
    property var actionQueue: []

    // Last volume this service wrote to the default output but has not yet
    // confirmed through a refresh. Relative steps (wheel, IPC) build on it so a
    // burst keeps summing while the model catches up; the post-write refresh
    // used to provide that freshness. A refresh drops it once it reports the
    // same value, and it expires so a failed write cannot skew later steps.
    property int outputVolumeInFlight: -1
    property double outputVolumeInFlightAt: 0
    readonly property int outputVolumeInFlightWindow: 1500

    property Timer outputVolumeTimer: Timer {
        id: outputVolumeTimer
        interval: 40
        repeat: true
        onTriggered: {
            if (root.pendingOutputVolume < 0) {
                outputVolumeTimer.running = false;
                return;
            }
            const value = root.pendingOutputVolume;
            const name = root.pendingOutputSink;
            root.pendingOutputVolume = -1;
            root.pendingOutputSink = "";
            if (name)
                root.applyVolumeToDevice("sink", name, value);
        }
    }

    property Timer inputVolumeTimer: Timer {
        id: inputVolumeTimer
        interval: 40
        repeat: true
        onTriggered: {
            if (root.pendingInputVolume < 0) {
                inputVolumeTimer.running = false;
                return;
            }
            const value = root.pendingInputVolume;
            const name = root.pendingInputSource;
            root.pendingInputVolume = -1;
            root.pendingInputSource = "";
            if (name)
                root.applyVolumeToDevice("source", name, value);
        }
    }

    // Pure parsing helpers live in audio/AudioParser.js. These wrappers keep
    // the service API (and the JSON guards with their diagnostics) intact.
    function clampPercent(value) {
        return AudioParser.clampPercent(value);
    }

    function volumePercent(device) {
        return AudioParser.volumePercent(device);
    }

    function channelList(volume) {
        return AudioParser.channelList(volume);
    }

    function describeDevice(entry) {
        return AudioParser.describeDevice(entry);
    }

    function deviceIcon(entry) {
        return AudioParser.deviceIcon(entry);
    }

    function parseDevices(text, kind) {
        // pactl prints nothing when it cannot reach the sound server (for
        // example while the server refuses new clients). Return null so the
        // caller keeps the previous list instead of clearing the device model.
        const raw = text.trim();
        if (!raw)
            return null;

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (err) {
            console.warn("AudioService: failed to parse", kind, err);
            return null;
        }
        if (!Array.isArray(parsed))
            return null;

        return AudioParser.devicesFromList(parsed, kind);
    }

    function parseCards(text) {
        const raw = text.trim();
        if (!raw)
            return null;

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (err) {
            console.warn("AudioService: failed to parse cards", err);
            return null;
        }
        if (!Array.isArray(parsed))
            return null;

        return AudioParser.cardsFromList(parsed);
    }

    // bluez_output.98_80_BB_41_CF_2D.1 -> bluez_card.98_80_BB_41_CF_2D
    function cardNameForSink(sinkName) {
        return AudioParser.cardNameForSink(sinkName);
    }

    function cardForSink(sinkName) {
        const name = root.cardNameForSink(sinkName);
        if (!name)
            return null;
        return root.cards.find(c => c.name === name) || null;
    }

    // Sets `isDefault` on a device list in place and reports whether a flag
    // actually moved. Callers publish the list themselves, so a refresh that
    // changes nothing does not rebuild the device rows a second time.
    function applyDefaults(devices, defaultName) {
        let changed = false;
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            const isDefault = device.name === defaultName;
            if (device.isDefault !== isDefault) {
                device.isDefault = isDefault;
                changed = true;
            }
        }
        return changed;
    }

    // Publishes a freshly parsed list with the default flag already applied, so
    // one subscriber event produces one model update instead of an assignment
    // followed by markDefaults()'s second one.
    function publishDevices(kind, devices) {
        root.applyDefaults(devices, kind === "sink" ? root.defaultSinkName : root.defaultSourceName);
        if (kind === "sink")
            root.sinks = devices;
        else
            root.sources = devices;
        root.markDefaults();
    }

    function markDefaults() {
        // Lists arrive here already marked by publishDevices(); only a default
        // that changed since the last publish is reassigned (and notified).
        if (root.applyDefaults(root.sinks, root.defaultSinkName))
            root.sinks = root.sinks.slice();
        if (root.applyDefaults(root.sources, root.defaultSourceName))
            root.sources = root.sources.slice();

        // A default endpoint can disappear from `pactl list` (e.g. a BlueZ
        // device). Keep it selectable by querying it directly once per refresh.
        const missingSink = root.defaultSinkName && !root.sinks.some(s => s.name === root.defaultSinkName);
        const missingSource = root.defaultSourceName && !root.sources.some(s => s.name === root.defaultSourceName);
        if ((missingSink || missingSource) && !root.detailProc.running) {
            root.detailProc.command = [
                "sh", "-c",
                (missingSink
                    ? 'echo SINK:$(pactl get-default-sink 2>/dev/null); pactl get-sink-volume "$(pactl get-default-sink 2>/dev/null)" 2>/dev/null; pactl get-sink-mute "$(pactl get-default-sink 2>/dev/null)" 2>/dev/null;'
                    : "")
                + (missingSource
                    ? 'echo SOURCE:$(pactl get-default-source 2>/dev/null); pactl get-source-volume "$(pactl get-default-source 2>/dev/null)" 2>/dev/null; pactl get-source-mute "$(pactl get-default-source 2>/dev/null)" 2>/dev/null;'
                    : "")
            ];
            root.detailProc.buffer = "";
            root.detailProc.running = true;
            return;
        }

        root.ensureLegacyVolume();
    }

    function ensureLegacyVolume() {
        const out = root.activeSink;
        if (!out)
            return;

        const vol = root.volumePercent(out);
        const wasReady = root.ready;
        if (wasReady && (root.volume !== vol || root.muted !== out.muted))
            root.volumeChangedManually(vol, out.muted);
        root.volume = vol;
        root.muted = out.muted;
        root.ready = true;
        // The write was confirmed, so the model value is authoritative again.
        if (root.outputVolumeInFlight >= 0 && vol === root.outputVolumeInFlight)
            root.outputVolumeInFlight = -1;
    }

    // Insert/update a default endpoint that pactl's list didn't contain.
    function applyFallback(kind, name, percent, muted) {
        if (!name)
            return;

        const devices = kind === "sink" ? root.sinks : root.sources;
        const channels = [{ value_percent: Math.max(0, Math.min(100, Math.round(percent))) + "%" }];
        let found = null;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].name === name) {
                found = devices[i];
                break;
            }
        }

        if (found) {
            found.channels = channels;
            found.muted = muted;
        } else {
            devices.push({
                name: name,
                description: name,
                icon: kind === "sink" ? "audio-card-analog" : "audio-input-microphone",
                channels: channels,
                muted: muted,
                isDefault: true
            });
        }

        // The list was mutated in place; publish it once so the rows redraw.
        if (kind === "sink")
            root.sinks = devices.slice();
        else
            root.sources = devices.slice();

        root.ensureLegacyVolume();
    }

    function refresh() {
        if (!sinkProc.running)
            sinkProc.running = true;
        if (!sourceProc.running)
            sourceProc.running = true;
        if (!defaultProc.running)
            defaultProc.running = true;
        if (!cardProc.running)
            cardProc.running = true;
    }

    function enqueueCommand(command, refreshAfter) {
        root.actionQueue.push({
            command: command,
            refreshAfter: refreshAfter === true
        });
        root.runNextAction();
    }

    function runNextAction() {
        if (root.actionProc.running || root.actionQueue.length === 0)
            return;
        const next = root.actionQueue.shift();
        root.actionProc.buffer = "";
        root.actionNeedsRefresh = next.refreshAfter === true;
        root.actionProc.command = next.command;
        root.actionProc.running = true;
    }

    // Volume and mute writes are reported by the subscriber (every write is an
    // `Event 'change' on sink/source`), so they must not pull a refresh.
    function applyVolumeToDevice(kind, name, percent) {
        const target = root.clampPercent(percent);
        if (kind === "sink") {
            if (name === root.defaultSinkName) {
                root.outputVolumeInFlight = target;
                root.outputVolumeInFlightAt = Date.now();
            }
            root.enqueueCommand(["pactl", "set-sink-volume", name, target + "%"]);
        } else {
            root.enqueueCommand(["pactl", "set-source-volume", name, target + "%"]);
        }
    }

    function toggleMuteForDevice(kind, name) {
        const command = kind === "sink"
            ? ["pactl", "set-sink-mute", name, "toggle"]
            : ["pactl", "set-source-mute", name, "toggle"];
        root.enqueueCommand(command);
    }

    // ── Public controls (settings page) ─────────────────────────────────────
    function setDefaultSink(name) {
        if (!name)
            return;
        // Set the default and move existing playback streams so the audio
        // follows the device the user just picked.
        const script = 'pactl set-default-sink "$1" && pactl list short sink-inputs'
            + ' | awk \'{print $1}\' | while read -r id; do'
            + ' pactl move-sink-input "$id" "$1" >/dev/null 2>&1; done';
        // The subscriber reports the server/sink-input changes, but the moved
        // streams and the fallback-device bookkeeping are safer to re-read.
        root.outputVolumeInFlight = -1;
        root.enqueueCommand(["sh", "-c", script, "sh", name], true);
    }

    function setDefaultSource(name) {
        if (!name)
            return;
        root.enqueueCommand(["pactl", "set-default-source", name], true);
    }

    // Switch the active Bluetooth codec by selecting its card profile
    // (e.g. "a2dp-sink-ldac"). The brief audio dropout is expected.
    function setCardProfile(cardName, profileName) {
        if (!cardName || !profileName)
            return;
        root.enqueueCommand(["pactl", "set-card-profile", cardName, profileName], true);
    }

    // These are throttled: every slider move updates the pending value, and
    // the timers above flush it to pactl a few times per second.
    function setOutputVolume(percent) {
        const sink = root.activeSink;
        if (!sink)
            return;
        const value = root.clampPercent(percent);
        root.pendingOutputVolume = value;
        root.pendingOutputSink = sink.name;
        if (!outputVolumeTimer.running)
            outputVolumeTimer.running = true;
    }

    function setInputVolume(percent) {
        const source = root.activeSource;
        if (!source)
            return;
        const value = root.clampPercent(percent);
        root.pendingInputVolume = value;
        root.pendingInputSource = source.name;
        if (!inputVolumeTimer.running)
            inputVolumeTimer.running = true;
    }

    function toggleOutputMute() {
        const sink = root.activeSink;
        if (sink)
            root.toggleMuteForDevice("sink", sink.name);
    }

    function toggleInputMute() {
        const source = root.activeSource;
        if (source)
            root.toggleMuteForDevice("source", source.name);
    }

    // Keep the old API working (bar scroll / shortcuts). It still targets the
    // default sink with a 5% step, matching previous behavior.
    function toggleMute() {
        root.toggleOutputMute();
    }

    function volumeUp() {
        root.setOutputVolume(root.stepBaseOutputVolume() + 2);
    }

    function volumeDown() {
        root.setOutputVolume(root.stepBaseOutputVolume() - 2);
    }

    // Newest known output level: the write still in flight, else the model.
    function stepBaseOutputVolume() {
        if (root.outputVolumeInFlight >= 0
                && Date.now() - root.outputVolumeInFlightAt < root.outputVolumeInFlightWindow)
            return root.outputVolumeInFlight;
        return root.volume;
    }

    // ── Processes ───────────────────────────────────────────────────────────

    // Live PipeWire/PulseAudio events. Any relevant object change schedules a
    // coalesced refresh; we don't spawn a process per event.
    // Обгортка pactl-subscribe.sh зупиняє підписника, що лишився від
    // попереднього запуску Quickshell, інакше кожен рестарт додавав би ще одне
    // клієнтське підключення до pipewire-pulse.
    property Process subProc: Process {
        command: [ShellPaths.pactlSubscribe]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("sink")
                    || data.includes("source")
                    || data.includes("server")
                    || data.includes("card")) {
                    root.debounce.restart();
                }
            }
        }
    }

    property Process sinkProc: Process {
        command: ["pactl", "-f", "json", "list", "sinks"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const devices = root.parseDevices(text, "sink");
                if (!devices)
                    return;
                root.publishDevices("sink", devices);
            }
        }
    }

    property Process sourceProc: Process {
        command: ["pactl", "-f", "json", "list", "sources"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const devices = root.parseDevices(text, "source");
                if (!devices)
                    return;
                root.publishDevices("source", devices);
            }
        }
    }

    property Process cardProc: Process {
        command: ["pactl", "-f", "json", "list", "cards"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const cards = root.parseCards(text);
                if (cards)
                    root.cards = cards;
            }
        }
    }

    property Process defaultProc: Process {
        command: [
            "sh", "-c",
            "echo SINK:$(pactl get-default-sink 2>/dev/null); echo SOURCE:$(pactl get-default-source 2>/dev/null)"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let changed = false;
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("SINK:")) {
                        const name = line.slice(5).trim();
                        if (name) {
                            // A different default means the in-flight level
                            // belonged to the previous device.
                            if (name !== root.defaultSinkName)
                                root.outputVolumeInFlight = -1;
                            root.defaultSinkName = name;
                            changed = true;
                        }
                    } else if (line.startsWith("SOURCE:")) {
                        const name = line.slice(7).trim();
                        if (name) {
                            root.defaultSourceName = name;
                            changed = true;
                        }
                    }
                }
                // Empty names mean pactl failed; keep the last valid defaults.
                if (changed)
                    root.markDefaults();
            }
        }
    }

    // Detail lookup for endpoints that vanished from pactl's main list.
    property Process detailProc: Process {
        running: false
        property string buffer: ""
        stdout: SplitParser { onRead: line => detailProc.buffer += line + "\n" }
        stderr: SplitParser { onRead: line => detailProc.buffer += line + "\n" }

        function parseFallback(text) {
            const lines = text.split("\n");
            let kind = "";
            let name = "";
            let volPercent = 0;
            let muted = false;

            for (let i = 0; i < lines.length; i++) {
                const raw = lines[i].trim();
                if (!raw)
                    continue;

                if (raw.startsWith("SINK:")) {
                    if (kind && name)
                        root.applyFallback(kind, name, volPercent, muted);
                    kind = "sink";
                    name = raw.slice(5).trim();
                    volPercent = 0;
                    muted = false;
                } else if (raw.startsWith("SOURCE:")) {
                    if (kind && name)
                        root.applyFallback(kind, name, volPercent, muted);
                    kind = "source";
                    name = raw.slice(7).trim();
                    volPercent = 0;
                    muted = false;
                } else if (raw.includes("[MUTED]")) {
                    muted = true;
                } else if (raw.indexOf("Volume:") === 0) {
                    const percents = raw.match(/\d+%/g) || [];
                    const values = percents.map(p => parseInt(p.replace("%", ""), 10)).filter(v => !isNaN(v));
                    if (values.length > 0)
                        volPercent = Math.round(values.reduce((a, b) => a + b, 0) / values.length);
                } else if (raw.indexOf("Mute:") === 0) {
                    muted = raw.toLowerCase().includes("yes") || raw.toLowerCase().includes("true");
                }
            }

            if (kind && name)
                root.applyFallback(kind, name, volPercent, muted);
        }

        onExited: () => {
            detailProc.parseFallback(detailProc.buffer);
            detailProc.buffer = "";
            root.markDefaults();
        }
    }

    // Single writer for every mutating action so we never overlap processes.
    property Process actionProc: Process {
        running: false
        property string buffer: ""
        stdout: SplitParser { onRead: line => actionProc.buffer += line + "\n" }
        stderr: SplitParser { onRead: line => actionProc.buffer += line + "\n" }
        onExited: code => {
            actionProc.buffer = "";
            if (code !== 0)
                console.warn("AudioService: action failed with code", code);
            // Read before runNextAction() loads the next command's flag.
            const needsRefresh = root.actionNeedsRefresh;
            root.runNextAction();
            if (needsRefresh)
                root.refresh();
        }
    }

    // Slow recovery net only: the subscriber above is the source of truth. This
    // exists so a pactl subscriber that died (e.g. after a pipewire-pulse
    // restart) cannot leave the bar permanently stale.
    property Timer pollTimer: Timer {
        interval: 300000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    // Одноразовий таймер після старту для початкового зчитування
    property Timer initTimer: Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: root.refresh()
    }
}
