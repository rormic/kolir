.pragma library

// Pure parsing helpers extracted verbatim from AudioService.
//
// Inputs arrive as parameters: the parsed JSON list from
// `pactl -f json list sinks|sources` or `list cards`, and plain device
// entries. Nothing here reads QML properties or service state, and the JSON
// guards plus their console diagnostics stay in the service, so the file also
// runs under node for comparison tests (see AGENTS.md).

function clampPercent(value) {
    return Math.max(0, Math.min(100, Math.round(value)))
}

function volumePercent(device) {
    if (!device || !Array.isArray(device.channels))
        return 0;
    const values = device.channels.map(ch => parseInt(String(ch.value_percent ?? "0").replace("%", ""), 10));
    if (values.length === 0 || values.some(isNaN))
        return 0;
    return clampPercent(values.reduce((a, b) => a + b, 0) / values.length);
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

function devicesFromList(parsed, kind) {
    const devices = parsed.map(entry => ({
        name: entry.name,
        description: describeDevice(entry),
        icon: deviceIcon(entry),
        channels: channelList(entry.volume),
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

function cardsFromList(parsed) {
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
