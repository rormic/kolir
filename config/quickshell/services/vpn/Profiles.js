.pragma library

// Pure helpers for the saved VPN profiles.
//
// Inputs arrive as the terse `nmcli -t` output or as a parsed field list;
// nothing here reads QML state or runs a command, so the file also works under
// node for comparison tests (see AGENTS.md).

// Same escaping rules as NetworkController.parseNmcli: a backslash escapes the
// next character, so `\:` is a literal colon and `\\` a literal backslash.
function parseTerse(text) {
    const lines = String(text || "").split("\n").filter(line => line.length > 0);

    return lines.map(line => {
        const fields = [];
        let current = "";
        let escape = false;
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (escape) {
                current += ch;
                escape = false;
            } else if (ch === "\\") {
                escape = true;
            } else if (ch === ":") {
                fields.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        fields.push(current);
        return fields;
    });
}

// NetworkManager reports a plain OpenVPN/WireGuard connection as `vpn`;
// newer releases use `wireguard`, and a kernel tunnel shows up as `tun`.
function isVpnType(type) {
    const value = String(type || "");
    return value === "vpn" || value === "wireguard" || value === "tun";
}

// `nmcli connection show` leaves DEVICE empty for a `vpn` profile because the
// tunnel interface is created by the plugin. The interface is the tun device
// whose CONNECTION column carries the profile name.
function resolveDevice(profile, deviceRows) {
    const name = typeof profile === "string"
        ? profile
        : String((profile && profile.name) || "");

    if (!name)
        return "";

    // A wireguard profile usually already carries its interface.
    if (typeof profile === "object" && profile && profile.device)
        return String(profile.device);

    const rows = typeof deviceRows === "string"
        ? parseTerse(deviceRows)
        : (Array.isArray(deviceRows) ? deviceRows : []);

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i] || [];
        if (String(row[0] || "") !== "tun")
            continue;
        if (String(row[2] || "") !== name)
            continue;
        return String(row[3] || "");
    }

    return "";
}

function buildProfiles(connectionText, deviceRows) {
    const rows = parseTerse(connectionText);
    const profiles = [];

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        const name = String(row[0] || "");
        const uuid = String(row[1] || "");
        const type = String(row[2] || "");
        if (!isVpnType(type))
            continue;

        const profile = {
            name: name,
            uuid: uuid,
            type: type,
            device: String(row[3] || ""),
            active: String(row[4] || "").toLowerCase() === "yes",
            autoconnect: String(row[5] || "").toLowerCase() === "yes"
        };

        if (!profile.device)
            profile.device = resolveDevice(profile, deviceRows);

        profiles.push(profile);
    }

    return profiles;
}

// `nmcli -t -f ipv4.never-default connection show <uuid>` prints the key and
// the value; a bare value is accepted as well.
function parseNeverDefault(text) {
    const rows = parseTerse(text);
    if (rows.length === 0)
        return false;

    const fields = rows[0];
    const value = fields.length > 1 ? fields[fields.length - 1] : fields[0];
    return String(value || "").trim().toLowerCase() === "yes";
}

// Secondaries arrive either as the raw nmcli line
// (`connection.secondaries:a;b`) or as the bare value.
function parseSecondaries(text) {
    const out = [];
    const lines = String(text || "").split("\n");

    for (let i = 0; i < lines.length; i++) {
        let value = lines[i];
        const keyEnd = value.indexOf(":");
        if (keyEnd > 0 && value.slice(0, keyEnd).indexOf(".") > 0)
            value = value.slice(keyEnd + 1);

        const parts = value.split(/[|;]/);
        for (let j = 0; j < parts.length; j++) {
            const entry = parts[j].trim();
            if (entry)
                out.push(entry);
        }
    }

    return out;
}

// `wg show <iface> dump` is tab-separated: the first line is the interface,
// every following line is a peer. An unused endpoint or key prints `(none)`,
// which is returned as an empty string.
function parseWgDump(text) {
    const lines = String(text || "").split("\n").filter(line => line.trim().length > 0);
    if (lines.length < 2)
        return null;

    const peer = lines[1].trim().split(/\s+/);
    if (peer.length < 7)
        return null;

    const endpoint = peer[2] === "(none)" ? "" : peer[2];
    return {
        endpoint: String(endpoint || ""),
        latestHandshake: parseInt(peer[4], 10) || 0,
        rx: parseInt(peer[5], 10) || 0,
        tx: parseInt(peer[6], 10) || 0
    };
}

function formatBytes(bytes) {
    const value = Math.max(0, Number(bytes) || 0);
    if (value < 1024)
        return Math.round(value) + " B";

    const units = ["KiB", "MiB", "GiB", "TiB"];
    let scaled = value / 1024;
    let unit = 0;
    while (scaled >= 1024 && unit < units.length - 1) {
        scaled /= 1024;
        unit++;
    }

    return scaled.toFixed(1) + " " + units[unit];
}

function formatHandshake(epochSeconds, nowSeconds) {
    const stamp = Number(epochSeconds) || 0;
    if (stamp <= 0)
        return "";

    const now = Number(nowSeconds) || 0;
    // A clock skew backwards still reads as a fresh handshake.
    const elapsed = Math.max(0, Math.floor(now - stamp));
    if (elapsed < 5)
        return "just now";
    if (elapsed < 60)
        return elapsed + " s ago";
    if (elapsed < 3600)
        return Math.floor(elapsed / 60) + " min ago";
    if (elapsed < 86400)
        return Math.floor(elapsed / 3600) + " h ago";
    return Math.floor(elapsed / 86400) + " d ago";
}

function humanType(type) {
    switch (String(type || "")) {
        case "wireguard":
            return "WireGuard";
        case "tun":
            return "Tunnel";
        case "vpn":
            return "VPN";
        default:
            return String(type || "");
    }
}
