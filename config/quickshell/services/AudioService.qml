pragma Singleton
import QtQuick
import Quickshell.Io

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
    property var actionQueue: []

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

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Math.round(value)))
    }

    function volumePercent(device) {
        if (!device || !Array.isArray(device.channels))
            return 0;
        const values = device.channels.map(ch => parseInt(String(ch.value_percent ?? "0").replace("%", ""), 10));
        if (values.length === 0 || values.some(isNaN))
            return 0;
        return root.clampPercent(values.reduce((a, b) => a + b, 0) / values.length);
    }

    function channelList(volume) {
        if (!volume)
            return [];
        if (Array.isArray(volume))
            return volume;
        const out = [];
        for (const key of Object.keys(volume)) {
            if (volume[key] && typeof volume[key] === "object")
                out.push(volume[key]);
        }
        return out;
    }

    function describeDevice(entry) {
        return entry.description
            || entry.properties?.["device.nick"]
            || entry.name
            || "";
    }

    function deviceIcon(entry) {
        const mediaClass = entry.properties?.["media.class"] || "";
        const icon = entry.properties?.["device.icon_name"] || "";

        if (mediaClass === "Audio/Source" && /microphone|mic/i.test(icon))
            return "audio-input-microphone";

        if (/headset|headphone/i.test(icon))
            return "audio-headset";
        if (/speaker/i.test(icon))
            return "speaker";
        if (/hdmi|displayport/i.test(icon))
            return "video-display";
        if (/microphone|mic/i.test(icon))
            return "audio-input-microphone";
        return mediaClass === "Audio/Source" ? "audio-input-microphone" : "audio-card-analog";
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

        const devices = parsed.map(entry => ({
            name: entry.name,
            description: root.describeDevice(entry),
            icon: root.deviceIcon(entry),
            channels: root.channelList(entry.volume),
            muted: !!entry.mute,
            isDefault: false
        }));

        // Hide monitor sources from the microphone picker (they mirror a sink).
        if (kind === "source") {
            return devices.filter(d =>
                !d.name.endsWith(".monitor")
                && d.channels.length > 0
            );
        }
        return devices;
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

        const cards = [];
        for (let i = 0; i < parsed.length; i++) {
            const entry = parsed[i];
            const name = entry.name || "";
            // Only BlueZ cards carry switchable A2DP codec profiles.
            if (!name.startsWith("bluez_card."))
                continue;

            const profiles = [];
            const raw = entry.profiles;
            // pactl -f json list cards returns profiles as an object keyed by
            // profile name; some versions use an array instead.
            if (Array.isArray(raw)) {
                for (const p of raw) {
                    if (p && p.name && p.available !== false)
                        profiles.push({ name: p.name, description: p.description || p.name });
                }
            } else if (raw && typeof raw === "object") {
                for (const key of Object.keys(raw)) {
                    const p = raw[key];
                    if (p && p.available !== false)
                        profiles.push({ name: key, description: (p && p.description) || key });
                }
            }

            cards.push({
                name: name,
                activeProfile: entry.active_profile || "",
                profiles: profiles
            });
        }
        return cards;
    }

    // bluez_output.98_80_BB_41_CF_2D.1 -> bluez_card.98_80_BB_41_CF_2D
    function cardNameForSink(sinkName) {
        if (!sinkName || !sinkName.startsWith("bluez_output."))
            return "";
        const mac = sinkName.slice("bluez_output.".length).split(".")[0];
        return mac ? "bluez_card." + mac : "";
    }

    function cardForSink(sinkName) {
        const name = root.cardNameForSink(sinkName);
        if (!name)
            return null;
        return root.cards.find(c => c.name === name) || null;
    }

    function markDefaults() {
        const nextSinks = [];
        for (let i = 0; i < root.sinks.length; i++) {
            const sink = root.sinks[i];
            sink.isDefault = sink.name === root.defaultSinkName;
            nextSinks.push(sink);
        }
        root.sinks = nextSinks;

        const nextSources = [];
        for (let j = 0; j < root.sources.length; j++) {
            const source = root.sources[j];
            source.isDefault = source.name === root.defaultSourceName;
            nextSources.push(source);
        }
        root.sources = nextSources;

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

    function enqueueCommand(command) {
        root.actionQueue.push({
            command: command
        });
        root.runNextAction();
    }

    function runNextAction() {
        if (root.actionProc.running || root.actionQueue.length === 0)
            return;
        const next = root.actionQueue.shift();
        root.actionProc.buffer = "";
        root.actionProc.command = next.command;
        root.actionProc.running = true;
    }

    function applyVolumeToDevice(kind, name, percent) {
        const target = root.clampPercent(percent);
        if (kind === "sink")
            root.enqueueCommand(["pactl", "set-sink-volume", name, target + "%"]);
        else
            root.enqueueCommand(["pactl", "set-source-volume", name, target + "%"]);
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
        root.enqueueCommand(["sh", "-c", script, "sh", name]);
    }

    function setDefaultSource(name) {
        if (!name)
            return;
        root.enqueueCommand(["pactl", "set-default-source", name]);
    }

    // Switch the active Bluetooth codec by selecting its card profile
    // (e.g. "a2dp-sink-ldac"). The brief audio dropout is expected.
    function setCardProfile(cardName, profileName) {
        if (!cardName || !profileName)
            return;
        root.enqueueCommand(["pactl", "set-card-profile", cardName, profileName]);
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
        root.setOutputVolume(root.volume + 2);
    }

    function volumeDown() {
        root.setOutputVolume(root.volume - 2);
    }

    // ── Processes ───────────────────────────────────────────────────────────

    // Live PipeWire/PulseAudio events. Any relevant object change schedules a
    // coalesced refresh; we don't spawn a process per event.
    property Process subProc: Process {
        command: ["pactl", "subscribe"]
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
                root.sinks = devices;
                root.markDefaults();
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
                root.sources = devices;
                root.markDefaults();
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
            root.runNextAction();
            root.refresh();
        }
    }

    // Occasional polling picks up changes made outside the shell.
    property Timer pollTimer: Timer {
        interval: 30000
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
