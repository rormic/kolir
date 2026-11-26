pragma Singleton
import QtQuick
import Quickshell.Io
import "."
import "vpn/Profiles.js" as Profiles

// NetworkManager VPN profiles, as the settings page and the bar chip see them.
//
// nmcli is the only source of truth. This singleton reads the saved profile
// list plus each profile's `never-default` flag, mirrors the active tunnel's
// address block and, for a WireGuard tunnel, the live peer counters from
// `wg show`. Every mutation (up/down, autoconnect, never-default, Wi-Fi
// secondaries) runs plain nmcli argv — never a shell — and then refreshes, so
// the model shows what NetworkManager actually stored rather than what the UI
// asked for.
//
// Import uses the shell's own FilePicker (the same grid the wallpaper hotkey
// and the portal requests open). The picker answers through a per-request JSON
// file: a timestamped sibling of ShellPaths.vpnImportResult, which is the whole
// stale-result guard — a late answer to a cancelled request can never be
// mistaken for the current one. The picker stays the only writer of that file;
// this service only reads it, reaps it, and forgets the path afterwards.
QtObject {
    id: root

    // ── Public state ───────────────────────────────────────────────────────
    // False until the first nmcli probe answered, so the UI can tell "unknown"
    // from "NetworkManager is not usable here".
    property bool probed: false
    property bool available: false

    // [{ name, uuid, type, device, active, autoconnect, neverDefault }]
    property var profiles: []
    property var activeProfile: null
    property bool connected: false

    property string activeName: ""
    property string activeType: ""
    property string activeUuid: ""
    property string activeDevice: ""

    // Active tunnel address block, parsed from `nmcli device show`.
    property string ip4: ""
    property string gateway4: ""
    property string dns: ""
    property string ip6: ""

    // WireGuard peer counters, already formatted for display. Every field stays
    // empty when the tunnel is not WireGuard or `wg` could not answer.
    property var wg: ({ endpoint: "", handshake: "", rx: "", tx: "" })

    // VPN profile uuids attached as `connection.secondaries` of the current
    // Wi-Fi profile, so the tunnel comes up together with that network.
    property var wifiSecondaries: []
    property string wifiProfile: ""

    property bool busy: false
    property string lastError: ""

    property bool importing: false
    property string importError: ""
    property string lastImported: ""

    property bool watching: false

    // ── Refresh plumbing ───────────────────────────────────────────────────
    // One full read at a time: overlapping timer ticks would otherwise
    // interleave their buffers and publish a half-updated model.
    property bool refreshing: false
    property bool connectionDone: false
    property bool deviceDone: false
    property var deviceRows: []
    property var rawProfiles: []

    // `nmcli connection show <id>` needs one call per profile for the settings
    // fields the summary listing does not expose (connection.secondaries and
    // ipv4.never-default are rejected by the field list of `connection show`
    // without an id, verified against nmcli 1.58).
    property var metaQueue: []
    property int metaIndex: 0
    property var metaNever: ({})
    property var metaSecondaries: ({})

    // ── Process plumbing ───────────────────────────────────────────────────
    // stdout/stderr text of the processes that are running, keyed by stream.
    // The processes themselves stay plain `Process` objects (no id and no extra
    // members), so every handler reads and clears its stream through these two
    // helpers.
    property var streams: ({})
    property string connectionText: ""
    property string actionLabel: ""
    property string importPath: ""
    property string wifiSecondaryTarget: ""

    // ── Import plumbing ────────────────────────────────────────────────────
    property string importId: ""
    property string importResultPath: ""
    property bool importHandled: false

    function appendStream(key, line) {
        root.streams[key] = (root.streams[key] || "") + line + "\n";
    }

    // Returns the collected text and empties the slot, so a retried process
    // never sees a previous run's tail.
    function takeStream(key) {
        const text = root.streams[key] || "";
        root.streams[key] = "";
        return text;
    }

    function emptyWg() {
        return { endpoint: "", handshake: "", rx: "", tx: "" };
    }

    function firstLine(text) {
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line !== "")
                return line;
        }
        return "";
    }

    function setWatching(value) {
        root.watching = value === true;
    }

    // ── Reading ────────────────────────────────────────────────────────────
    function refresh() {
        if (root.refreshing)
            return;

        root.refreshing = true;
        root.connectionDone = false;
        root.deviceDone = false;
        root.connectionText = "";
        root.metaQueue = [];
        root.metaIndex = 0;
        root.metaNever = ({});
        root.metaSecondaries = ({});

        // Only the read streams belong to this refresh; an action that is
        // still running keeps its own buffer so its stderr can still explain a
        // failure.
        root.takeStream("connection");
        root.takeStream("device");
        root.takeStream("meta");
        root.takeStream("detail");
        root.takeStream("wg");

        root.connectionProc.running = true;
        root.deviceProc.running = true;
    }

    // Both processes feed the same build step; whichever lands last starts it.
    function maybeBuild() {
        if (!root.connectionDone || !root.deviceDone)
            return;

        if (!root.available) {
            // No NetworkManager answer: nothing is bound to a Wi-Fi profile any
            // more, so the page must not keep offering a stale toggle.
            root.wifiProfile = "";
            root.wifiSecondaries = [];
            root.publishProfiles([]);
            root.refreshing = false;
            return;
        }

        root.rawProfiles = Profiles.buildProfiles(
            root.connectionText, root.deviceRows);
        root.startMetaWalk();
    }

    // The summary listing carries every profile field the UI needs except
    // never-default and secondaries, so ask nmcli once per profile. The queue
    // also carries the active Wi-Fi profile (by name) whose secondaries list
    // which VPNs come up with that network.
    function startMetaWalk() {
        const queue = [];
        for (let i = 0; i < root.rawProfiles.length; i++) {
            const uuid = String(root.rawProfiles[i].uuid || "");
            if (uuid !== "")
                queue.push(uuid);
        }

        const wifi = root.wifiConnectionName(root.deviceRows);
        if (wifi !== "") {
            let seen = false;
            for (let i = 0; i < queue.length; i++) {
                if (queue[i] === wifi)
                    seen = true;
            }
            if (!seen)
                queue.push(wifi);
        }

        root.metaQueue = queue;
        root.metaIndex = 0;
        root.walkMeta();
    }

    function walkMeta() {
        if (root.metaIndex >= root.metaQueue.length) {
            root.finishProfiles();
            return;
        }

        root.metaProc.command = [
            "nmcli", "-t", "-f", "ipv4.never-default,connection.secondaries",
            "connection", "show", String(root.metaQueue[root.metaIndex]),
        ];
        root.metaProc.running = true;
    }

    function readMeta(entry, text) {
        // Two key:value lines in the requested order. Split them by prefix
        // instead of by position so a future nmcli reordering cannot feed the
        // never-default value into the secondaries parser.
        const lines = String(text || "").split("\n");
        let neverLine = "";
        let secondaryLine = "";
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("ipv4.never-default:") === 0 && neverLine === "")
                neverLine = lines[i];
            else if (lines[i].indexOf("connection.secondaries:") === 0
                && secondaryLine === "")
                secondaryLine = lines[i];
        }

        root.metaNever[entry] = Profiles.parseNeverDefault(neverLine);
        root.metaSecondaries[entry] = Profiles.parseSecondaries(secondaryLine);
    }

    function finishProfiles() {
        const list = [];
        for (let i = 0; i < root.rawProfiles.length; i++) {
            const raw = root.rawProfiles[i];
            const uuid = String(raw.uuid || "");
            list.push({
                name: String(raw.name || ""),
                uuid: uuid,
                type: String(raw.type || ""),
                device: String(raw.device || ""),
                active: raw.active === true,
                autoconnect: raw.autoconnect === true,
                neverDefault: root.metaNever[uuid] === true,
            });
        }

        const wifi = root.wifiConnectionName(root.deviceRows);
        root.wifiProfile = wifi;

        root.publishProfiles(list);
        root.wifiSecondaries = root.vpnSecondaries(wifi);
        root.refreshing = false;
    }

    // Publishes the profile list and mirrors the first active one into the
    // flat properties the bar chip reads synchronously.
    function publishProfiles(list) {
        let active = null;
        for (let i = 0; i < list.length; i++) {
            if (list[i].active) {
                active = list[i];
                break;
            }
        }

        root.profiles = list;
        root.activeProfile = active;
        root.connected = active !== null;
        root.activeName = active ? active.name : "";
        root.activeType = active ? active.type : "";
        root.activeUuid = active ? active.uuid : "";
        root.activeDevice = active ? active.device : "";

        if (!active || root.activeDevice === "") {
            root.clearDetails();
            return;
        }

        root.refreshDetails(root.activeDevice, root.activeType);
    }

    function clearDetails() {
        root.ip4 = "";
        root.gateway4 = "";
        root.dns = "";
        root.ip6 = "";
        root.wg = root.emptyWg();
    }

    function refreshDetails(device, type) {
        root.detailProc.command = ["nmcli", "-t", "device", "show", device];
        if (!root.detailProc.running)
            root.detailProc.running = true;

        if (String(type) === "wireguard") {
            root.wgProc.command = ["wg", "show", device, "dump"];
            if (!root.wgProc.running)
                root.wgProc.running = true;
        } else {
            root.wg = root.emptyWg();
        }
    }

    // Same key layout as NetworkController.parseDeviceDetails, reduced to the
    // fields a tunnel actually reports.
    function parseDetails(text) {
        const lines = String(text || "").split("\n");
        const out = { ip4: "", gateway4: "", dns: [], ip6: "" };
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line)
                continue;
            const idx = line.indexOf(":");
            if (idx < 0)
                continue;
            const key = line.slice(0, idx);
            const val = line.slice(idx + 1);
            if (key.indexOf("IP4.ADDRESS") === 0 && !out.ip4)
                out.ip4 = val;
            else if (key === "IP4.GATEWAY" && val && val !== "--")
                out.gateway4 = val;
            else if (key.indexOf("IP4.DNS") === 0 && val)
                out.dns.push(val);
            else if (key.indexOf("IP6.ADDRESS") === 0 && !out.ip6 && val)
                out.ip6 = val;
        }
        return out;
    }

    // The active Wi-Fi profile name, used as the "current network" whose
    // secondaries the page lists.
    function wifiConnectionName(rows) {
        const list = Array.isArray(rows) ? rows : [];
        for (let i = 0; i < list.length; i++) {
            const row = list[i] || [];
            if (String(row[0] || "") !== "wifi")
                continue;
            if (String(row[1] || "").indexOf("connected") !== 0)
                continue;
            const name = String(row[2] || "");
            if (name !== "" && name !== "--")
                return name;
        }
        return "";
    }

    // Keeps only uuids that really are saved VPN profiles, so a stale secondary
    // entry cannot leak into the toggle list.
    function vpnSecondaries(wifiProfile) {
        const entries = root.metaSecondaries[wifiProfile];
        if (!Array.isArray(entries))
            return [];

        const out = [];
        for (let i = 0; i < entries.length; i++) {
            const id = String(entries[i] || "");
            if (id === "")
                continue;
            for (let j = 0; j < root.profiles.length; j++) {
                if (root.profiles[j].uuid === id) {
                    out.push(id);
                    break;
                }
            }
        }
        return out;
    }

    // Reads the secondaries of an arbitrary Wi-Fi profile, for a page that lets
    // the user bind VPNs to a network other than the active one.
    function refreshWifiSecondaries(wifiProfile) {
        const name = String(wifiProfile || "");
        if (name === "") {
            root.wifiProfile = "";
            root.wifiSecondaries = [];
            return;
        }

        if (root.wifiSecondaryProc.running)
            root.wifiSecondaryProc.running = false;

        root.wifiSecondaryTarget = name;
        root.wifiSecondaryProc.command = [
            "nmcli", "-t", "-f", "connection.secondaries", "connection",
            "show", name,
        ];
        root.wifiSecondaryProc.running = true;
    }

    // ── Profile lookup and actions ─────────────────────────────────────────
    function findProfile(value) {
        if (value === null || value === undefined)
            return null;
        if (typeof value === "object")
            return value;

        const key = String(value);
        for (let i = 0; i < root.profiles.length; i++) {
            const profile = root.profiles[i];
            if (profile.uuid === key || profile.name === key)
                return profile;
        }
        return null;
    }

    function startAction(command, label) {
        if (root.busy)
            return false;

        root.lastError = "";
        root.busy = true;
        root.actionLabel = label;
        root.actionProc.command = command;
        root.actionProc.running = true;
        return true;
    }

    function activate(profile) {
        const target = root.findProfile(profile);
        if (!target)
            return;

        root.startAction(
            ["nmcli", "connection", "up", target.uuid || target.name],
            "Could not activate " + target.name);
    }

    function deactivate(profile) {
        const target = root.findProfile(profile);
        if (!target)
            return;

        root.startAction(
            ["nmcli", "connection", "down", target.uuid || target.name],
            "Could not deactivate " + target.name);
    }

    // Null profile toggles the active tunnel, or the first saved one.
    function toggle(profile) {
        let target = root.findProfile(profile);
        if (!target)
            target = root.activeProfile;
        if (!target && root.profiles.length > 0)
            target = root.profiles[0];
        if (!target)
            return;

        if (target.active)
            root.deactivate(target);
        else
            root.activate(target);
    }

    function setAutoconnect(profile, enabled) {
        const target = root.findProfile(profile);
        if (!target)
            return;

        root.startAction([
            "nmcli", "connection", "modify", target.uuid || target.name,
            "connection.autoconnect", enabled ? "yes" : "no",
        ], "Could not change autoconnect");
    }

    // Both families are written together: a tunnel that keeps the default
    // route on IPv4 but not on IPv6 would be a half-applied setting.
    function setNeverDefault(profile, enabled) {
        const target = root.findProfile(profile);
        if (!target)
            return;

        const flag = enabled ? "yes" : "no";
        root.startAction([
            "nmcli", "connection", "modify", target.uuid || target.name,
            "ipv4.never-default", flag, "ipv6.never-default", flag,
        ], "Could not change the default route");
    }

    function setWifiSecondary(wifiProfile, vpnProfile, enabled) {
        const wifi = String(wifiProfile || root.wifiProfile || "");
        const target = root.findProfile(vpnProfile);
        if (wifi === "" || !target)
            return;

        root.startAction([
            "nmcli", "connection", "modify", wifi,
            (enabled ? "+" : "-") + "connection.secondaries",
            target.uuid || target.name,
        ], "Could not change the Wi-Fi secondaries");
    }

    // ── Import ─────────────────────────────────────────────────────────────
    function uriToPath(uri) {
        let path = String(uri || "");
        if (path.indexOf("file://") === 0)
            path = path.slice("file://".length);
        try {
            path = decodeURIComponent(path);
        } catch (error) {
            // A malformed escape is not worth failing the import over; nmcli
            // reports the path it cannot read.
        }
        return path;
    }

    function importTypeFor(path) {
        const lower = String(path || "").toLowerCase();
        if (lower.endsWith(".conf"))
            return "wireguard";
        if (lower.endsWith(".ovpn"))
            return "openvpn";
        return "";
    }

    function importProfile() {
        if (root.importing)
            return;

        root.importError = "";
        root.importHandled = false;
        root.importing = true;

        const stamp = Date.now();
        root.importId = "vpn-import-" + stamp;
        // Timestamped sibling of ShellPaths.vpnImportResult. Only one import
        // may run at a time, but a request the user abandoned (or a picker
        // answer that arrives after the timeout) must never be read as the
        // current one, and a distinct path is the cheapest guarantee.
        const base = ShellPaths.vpnImportResult;
        root.importResultPath = base.endsWith(".json")
            ? base.slice(0, base.length - ".json".length) + "-" + stamp + ".json"
            : base + "-" + stamp;

        importTimeout.restart();

        // Seed an empty object first: the FileView below starts watching as
        // soon as the path is set, and a missing file would log a read error
        // on every open. `{}` decodes to "no answer yet".
        root.importSeedProc.command = [
            "sh", "-c", "mkdir -p \"$1\" && printf %s \"{}\" > \"$2\"",
            "vpn-import", ShellPaths.runtimeStateDir, root.importResultPath,
        ];
        root.importSeedProc.running = true;
    }

    function startPicker() {
        if (!root.importing)
            return;

        root.pickerProc.command = [
            "qs", "-p", ShellPaths.shellDir,
            "ipc", "--any-display", "call", "filePicker", "open",
            JSON.stringify({
                id: root.importId,
                mode: "openFile",
                title: "Import VPN profile",
                acceptLabel: "Import",
                filters: [
                    { name: "VPN profiles", patterns: ["*.conf", "*.ovpn"] },
                    { name: "All files", patterns: ["*"] },
                ],
                resultPath: root.importResultPath,
            }),
        ];
        root.pickerProc.running = true;
    }

    function handleImportResult(text) {
        if (!root.importing || root.importHandled)
            return;

        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            // The picker may still be writing the file; the next change is a
            // complete document.
            return;
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
            return;

        if (parsed.cancelled === true) {
            root.finishImport("", "");
            return;
        }

        const uris = Array.isArray(parsed.uris) ? parsed.uris : [];
        if (uris.length === 0)
            return;

        root.importHandled = true;
        const path = root.uriToPath(uris[0]);
        const type = root.importTypeFor(path);
        if (type === "") {
            root.finishImport("", "Unsupported profile");
            return;
        }

        root.runImport(path, type);
    }

    // Shared by the picker result and the `importProfile(path)` IPC call.
    function runImport(path, type) {
        root.importPath = path;
        root.importProc.command = [
            "nmcli", "connection", "import", "type", type, "file", path,
        ];
        root.importProc.running = true;
        root.importing = true;
    }

    // Ends an import attempt: clears the busy flag, removes the result file and
    // forgets the watched path so a later answer cannot be read.
    function finishImport(imported, error) {
        root.importing = false;
        root.importHandled = true;
        root.importError = String(error || "");
        if (String(imported || "") !== "")
            root.lastImported = String(imported);

        importTimeout.stop();
        root.deleteImportFile();
        root.importResultPath = "";
    }

    function deleteImportFile() {
        if (root.importResultPath === "")
            return;

        root.cleanupProc.command = ["rm", "-f", "--", root.importResultPath];
        root.cleanupProc.running = true;
    }

    function cancelImport() {
        if (!root.importing) {
            root.importResultPath = "";
            return;
        }

        // Close the panel through the same IPC the portal backend uses, so an
        // open picker never outlives the request it was opened for.
        root.cancelProc.command = [
            "qs", "-p", ShellPaths.shellDir,
            "ipc", "--any-display", "call", "filePicker", "cancel",
            root.importId,
        ];
        root.cancelProc.running = true;

        root.finishImport("", "");
    }

    // `nmcli` reports the imported profile name in its success line; fall back
    // to the file name when the output changes.
    function importedName(text, path) {
        const match = String(text || "").match(/'([^']+)'/);
        if (match && match[1])
            return match[1];

        const slash = String(path || "").lastIndexOf("/");
        return slash >= 0 ? String(path).slice(slash + 1) : String(path || "");
    }

    // ── Processes: reading ─────────────────────────────────────────────────
    property Process connectionProc: Process {
        command: [
            "nmcli", "-t", "-f",
            "NAME,UUID,TYPE,DEVICE,ACTIVE,AUTOCONNECT", "connection", "show",
        ]
        stdout: SplitParser {
            onRead: line => root.appendStream("connection", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("connection");

            // A non-zero exit covers both "nmcli is not installed" and
            // "NetworkManager is not answering"; either way the card shows
            // "unavailable" instead of a stale profile list.
            root.probed = true;
            root.available = exitCode === 0;
            root.connectionText = root.available ? text : "";
            root.connectionDone = true;
            root.maybeBuild();
        }
    }

    property Process deviceProc: Process {
        command: [
            "nmcli", "-t", "-f", "TYPE,STATE,CONNECTION,DEVICE",
            "device", "status",
        ]
        stdout: SplitParser {
            onRead: line => root.appendStream("device", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("device");
            root.deviceRows = exitCode === 0 ? Profiles.parseTerse(text) : [];
            root.deviceDone = true;
            root.maybeBuild();
        }
    }

    property Process metaProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("meta", line)
        }
        onExited: (exitCode, exitStatus) => {
            const entry = String(root.metaQueue[root.metaIndex] || "");
            const text = root.takeStream("meta");

            // A profile without an IP4 setting may reject the field list; the
            // defaults (never-default off, no secondaries) are the safe answer
            // and the next refresh retries.
            if (exitCode === 0 && entry !== "")
                root.readMeta(entry, text);

            root.metaIndex++;
            root.walkMeta();
        }
    }

    property Process detailProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("detail", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("detail");
            if (exitCode !== 0)
                return;

            const detail = root.parseDetails(text);
            root.ip4 = detail.ip4;
            root.gateway4 = detail.gateway4;
            root.dns = detail.dns.join(", ");
            root.ip6 = detail.ip6;
        }
    }

    property Process wgProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("wg", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("wg");

            // The tunnel may have dropped between the two calls; keeping the
            // previous counters would look like live traffic.
            const dump = exitCode === 0 ? Profiles.parseWgDump(text) : null;
            if (dump === null) {
                root.wg = root.emptyWg();
                return;
            }

            root.wg = {
                endpoint: dump.endpoint,
                handshake: Profiles.formatHandshake(
                    dump.latestHandshake, Date.now() / 1000),
                rx: Profiles.formatBytes(dump.rx),
                tx: Profiles.formatBytes(dump.tx),
            };
        }
    }

    property Process wifiSecondaryProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("wifiSecondaries", line)
        }
        onExited: (exitCode, exitStatus) => {
            const target = root.wifiSecondaryTarget;
            const text = root.takeStream("wifiSecondaries");
            root.wifiSecondaryTarget = "";

            root.wifiProfile = target;
            if (exitCode !== 0) {
                root.wifiSecondaries = [];
                return;
            }

            const entries = Profiles.parseSecondaries(text);
            const out = [];
            for (let i = 0; i < entries.length; i++) {
                for (let j = 0; j < root.profiles.length; j++) {
                    if (root.profiles[j].uuid === entries[i]) {
                        out.push(entries[i]);
                        break;
                    }
                }
            }
            root.wifiSecondaries = out;
        }
    }

    // ── Processes: actions ─────────────────────────────────────────────────
    property Process actionProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("action", line)
        }
        stderr: SplitParser {
            onRead: line => root.appendStream("action", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("action");
            const label = root.actionLabel;
            root.actionLabel = "";
            root.busy = false;

            if (exitCode !== 0)
                root.lastError = root.firstLine(text) || label;

            root.refresh();
        }
    }

    // ── Processes: import ──────────────────────────────────────────────────
    property Process importSeedProc: Process {
        stderr: SplitParser {
            onRead: line => root.appendStream("seedError", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("seedError");

            if (exitCode !== 0) {
                root.importError = root.firstLine(text)
                    || "Could not prepare the file picker";
                root.finishImport("", root.importError);
                return;
            }

            root.startPicker();
        }
    }

    property Process pickerProc: Process {
        stderr: SplitParser {
            onRead: line => root.appendStream("pickerError", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("pickerError");

            // A successful call only means the request was accepted; the
            // answer arrives through the result file. A failure here means no
            // picker is running (shell down or an IPC error).
            if (exitCode !== 0 && root.importing) {
                root.importError = root.firstLine(text)
                    || "Could not open the file picker";
                root.finishImport("", root.importError);
            }
        }
    }

    property Process importProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("import", line)
        }
        stderr: SplitParser {
            onRead: line => root.appendStream("import", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("import");
            const path = root.importPath;
            root.importPath = "";

            if (exitCode !== 0) {
                root.finishImport("", root.firstLine(text) || "Import failed");
                return;
            }

            root.finishImport(root.importedName(text, path), "");
            root.refresh();
        }
    }

    property Process cleanupProc: Process {
        running: false
    }

    property Process cancelProc: Process {
        running: false
    }

    // The picker file is watched, not polled: `onFileChanged` reloads and
    // `onLoaded` decodes, exactly like Colors.qml follows colors.json.
    property FileView importView: FileView {
        path: root.importResultPath
        watchChanges: true
        printErrors: false

        onFileChanged: this.reload()
        onLoaded: root.handleImportResult(this.text())
    }

    // A request the picker never answered (the panel was killed, the session
    // locked) must not leave the import spinner on forever.
    property Timer importTimeout: Timer {
        interval: 600000
        repeat: false
        onTriggered: {
            if (!root.importing)
                return;
            root.finishImport("", "The file picker did not answer");
        }
    }

    // One read per tick. The interval is slow while nmcli is missing and
    // faster while a page watches, so a closed settings page never keeps a
    // 5 s nmcli loop alive.
    property Timer poll: Timer {
        interval: !root.probed ? 60000 : root.watching ? 5000 : 15000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    property IpcHandler ipc: IpcHandler {
        target: "vpn"

        function status(): string {
            return JSON.stringify({
                available: root.available,
                connected: root.connected,
                active: root.activeProfile ? root.activeProfile.name : "",
                profiles: root.profiles,
                ip4: root.ip4,
                dns: root.dns,
                wg: root.wg,
                wifiProfile: root.wifiProfile,
                wifiSecondaries: root.wifiSecondaries,
                busy: root.busy,
                lastError: root.lastError,
                importing: root.importing,
            });
        }

        function up(name: string): string {
            const target = root.findProfile(name);
            if (!target)
                return "unknown profile: " + name;
            root.activate(target);
            return "activating " + target.name;
        }

        function down(name: string): string {
            const target = root.findProfile(name);
            if (!target)
                return "unknown profile: " + name;
            if (!target.active)
                return "not connected: " + target.name;
            root.deactivate(target);
            return "deactivating " + target.name;
        }

        // `import` is a reserved word in QML, so the IPC method is `importFile`.
        // Scripts use this path; the card calls importProfile() to run the
        // picker.
        function importFile(path: string): string {
            const target = String(path || "");
            if (target === "")
                return "no path";

            const type = root.importTypeFor(target);
            if (type === "")
                return "unsupported profile: " + target;

            root.runImport(target, type);
            return "importing " + target;
        }

        function refresh(): string {
            if (root.refreshing)
                return "busy";
            root.refresh();
            return "refreshing";
        }
    }
}
