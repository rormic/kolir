.pragma library

// Pure parsing helpers for `tailscale status --json`.
//
// The daemon's answer is a single JSON document; nothing here reads QML state,
// so the file also works under node for comparison tests (see AGENTS.md). The
// caller keeps the raw text and the diagnostics, this file only shapes it.

function stringList(values) {
    if (!Array.isArray(values))
        return [];

    const out = [];
    for (let i = 0; i < values.length; i++) {
        if (typeof values[i] === "string" && values[i] !== "")
            out.push(values[i]);
    }
    return out;
}

function stripTrailingDot(value) {
    const text = String(value || "");
    return text.endsWith(".") ? text.slice(0, -1) : text;
}

// Peer is a map keyed by node ID in every release so far, but an array is
// accepted too so a future format change cannot break the parse.
function peerEntries(data) {
    const peers = data && data.Peer;
    if (!peers || typeof peers !== "object")
        return [];

    const out = [];
    if (Array.isArray(peers)) {
        for (let i = 0; i < peers.length; i++) {
            const peer = peers[i];
            if (!peer || typeof peer !== "object")
                continue;
            out.push({ id: String(peer.ID || String(i)), peer: peer });
        }
        return out;
    }

    const keys = Object.keys(peers);
    for (let i = 0; i < keys.length; i++) {
        const peer = peers[keys[i]];
        if (!peer || typeof peer !== "object")
            continue;
        out.push({ id: String(peer.ID || keys[i]), peer: peer });
    }
    return out;
}

// A peer without a host name still needs a label: the MagicDNS name, the first
// address, and finally the node ID.
function peerName(peer, id) {
    const hostName = String((peer && peer.HostName) || "");
    if (hostName)
        return hostName;

    const dnsName = stripTrailingDot((peer && peer.DNSName) || "");
    if (dnsName)
        return dnsName;

    const ips = stringList(peer && peer.TailscaleIPs);
    if (ips.length > 0)
        return ips[0];

    return id;
}

function parseStatus(text) {
    let data = null;
    try {
        data = JSON.parse(String(text || ""));
    } catch (error) {
        return null;
    }

    if (!data || typeof data !== "object" || Array.isArray(data))
        return null;

    const self = data.Self && typeof data.Self === "object" ? data.Self : {};
    const entries = peerEntries(data);

    const exitNodes = [];
    let peersOnline = 0;
    for (let i = 0; i < entries.length; i++) {
        const peer = entries[i].peer;
        const id = entries[i].id;
        if (peer.Online === true)
            peersOnline++;
        if (peer.ExitNodeOption !== true)
            continue;
        exitNodes.push({
            id: id,
            name: peerName(peer, id),
            dnsName: stripTrailingDot(peer.DNSName || ""),
            online: peer.Online === true
        });
    }

    exitNodes.sort((left, right) => {
        const nameLeft = left.name.toLowerCase();
        const nameRight = right.name.toLowerCase();
        if (nameLeft < nameRight)
            return -1;
        if (nameLeft > nameRight)
            return 1;
        return left.id.localeCompare(right.id);
    });

    let exitNode = null;
    const status = data.ExitNodeStatus;
    if (status && typeof status === "object") {
        const rawId = String(status.ID || "");
        if (rawId) {
            exitNode = { id: rawId, name: rawId };
            for (let i = 0; i < entries.length; i++) {
                const peer = entries[i].peer;
                if (entries[i].id !== rawId && String(peer.HostName || "") !== rawId)
                    continue;
                exitNode.name = peerName(peer, entries[i].id);
                break;
            }
        }
    }

    return {
        backendState: typeof data.BackendState === "string" ? data.BackendState : "",
        hostName: String(self.HostName || ""),
        dnsName: stripTrailingDot(self.DNSName || ""),
        ips: stringList(self.TailscaleIPs),
        online: self.Online === true,
        peersTotal: entries.length,
        peersOnline: peersOnline,
        exitNodes: exitNodes,
        exitNode: exitNode,
        health: stringList(data.Health)
    };
}
