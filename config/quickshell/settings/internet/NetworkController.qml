import QtQuick
import Quickshell.Io

// nmcli-backed state and processes for the Internet page. The page instantiates
// exactly one controller and binds its UI to these properties; ownership stays
// inside the page, so polling can follow page visibility.
Item {
    id: root

    // Mirrors the owning page's visibility.
    property bool active: false

    // The page owns the form state transitions; the controller asks for a
    // reset when a connection succeeds or Wi-Fi is turned off.
    signal resetRequested()

    // ── State ──────────────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property bool hasWifiDevice: false
    property string wifiDevice: ""
    property string activeWifi: ""
    property string ethernetState: "Unavailable"
    property string ethernetConnection: ""
    property string ethernetDevice: ""
    property string ethernetMac: ""
    property string ethernetSpeed: ""
    property string ethernetIp4: ""
    property string ethernetGateway4: ""
    property string ethernetDns: ""
    property string ethernetIp6: ""
    property bool ethernetDetailsExpanded: false
    property bool scanning: false
    property bool busy: false
    property string lastError: ""

    property var wifiNetworks: []
    property var savedWifi: ({})

    // Password / hidden forms
    property string formMode: "" // "", "password", "hidden"
    property var formNetwork: null
    property string formSsid: ""
    property string formPassword: ""
    property bool formShowPassword: false
    property bool formBusy: false
    property string formError: ""
    property int formSecurityIndex: 1 // 0 open, 1 WPA/WPA2

    readonly property bool wifiConnected: activeWifi !== ""

    function isSecure(sec) {
        return !!sec && sec !== "" && sec !== "--";
    }

    function parseNmcli(text) {
        const lines = text.split("\n").filter(l => l.length > 0);
        return lines.map(line => {
            const out = [];
            let cur = "";
            let esc = false;
            for (let i = 0; i < line.length; i++) {
                const ch = line[i];
                if (esc) {
                    cur += ch;
                    esc = false;
                } else if (ch === "\\") {
                    esc = true;
                } else if (ch === ":") {
                    out.push(cur);
                    cur = "";
                } else {
                    cur += ch;
                }
            }
            out.push(cur);
            return out;
        });
    }

    function refreshAll(rescan) {
        root.lastError = "";
        radioProc.buffer = "";
        radioProc.running = true;
        statusProc.buffer = "";
        statusProc.running = true;
        savedProc.buffer = "";
        savedProc.running = true;
        if (root.wifiEnabled || rescan) {
            scanProc.buffer = "";
            scanProc.command = [
                "nmcli", "-t",
                "-f", "IN-USE,SSID,SECURITY,SIGNAL,BSSID,DEVICE",
                "device", "wifi", "list"
            ].concat(rescan ? ["--rescan", "yes"] : ["--rescan", "no"]);
            if (!scanProc.running) {
                scanProc.running = true;
                if (rescan)
                    root.scanning = true;
            }
        }
        if (root.ethernetDevice) {
            ethDetailProc.buffer = "";
            ethDetailProc.command = ["nmcli", "-t", "device", "show", root.ethernetDevice];
            if (!ethDetailProc.running)
                ethDetailProc.running = true;
        }
    }

    function connectNetwork(net) {
        if (!net)
            return;
        root.lastError = "";
        if (net.connected) {
            actionProc.buffer = "";
            actionProc.command = ["nmcli", "device", "disconnect", net.device || root.wifiDevice];
            actionProc.running = true;
            root.busy = true;
            return;
        }
        if (root.isSecure(net.security) && !root.savedWifi[net.ssid]) {
            root.formMode = "password";
            root.formNetwork = net;
            root.formSsid = net.ssid;
            root.formPassword = "";
            root.formShowPassword = false;
            root.formError = "";
            return;
        }
        actionProc.buffer = "";
        actionProc.command = ["nmcli", "device", "wifi", "connect", net.ssid];
        if (net.bssid)
            actionProc.command = actionProc.command.concat(["bssid", net.bssid]);
        actionProc.running = true;
        root.busy = true;
    }

    function setWifiEnabled(enabled) {
        actionProc.buffer = "";
        actionProc.command = ["nmcli", "radio", "wifi", enabled ? "on" : "off"];
        actionProc.running = true;
        root.busy = true;
        if (!enabled)
            root.resetRequested();
    }

    function forgetNetwork(net) {
        if (!net || !net.ssid)
            return;
        root.lastError = "";
        actionProc.buffer = "";
        actionProc.command = ["nmcli", "connection", "delete", net.ssid];
        actionProc.running = true;
        root.busy = true;
    }

    function submitPasswordForm() {
        if (!formNetwork || formBusy)
            return;
        root.formError = "";
        root.formBusy = true;
        formProc.buffer = "";
        formProc.command = ["nmcli", "device", "wifi", "connect", formNetwork.ssid, "password", formPassword];
        if (formNetwork.bssid)
            formProc.command = formProc.command.concat(["bssid", formNetwork.bssid]);
        formProc.running = true;
    }

    function submitHiddenForm() {
        if (!formSsid || formBusy)
            return;
        root.formError = "";
        root.formBusy = true;
        formProc.buffer = "";
        const cmd = ["nmcli", "device", "wifi", "connect", formSsid, "hidden", "yes"];
        if (formSecurityIndex === 1)
            cmd.push("password", formPassword);
        formProc.command = cmd;
        formProc.running = true;
    }

    Component.onCompleted: refreshAll(false)
    onActiveChanged: {
        if (active) {
            refreshDelay.restart();
        } else {
            refreshDelay.stop();
            root.resetRequested();
        }
    }

    // Defer the first nmcli refresh until the page transition has finished,
    // so process startup doesn't compete with animation frames.
    Timer {
        id: refreshDelay
        interval: 200
        onTriggered: if (root.active) root.refreshAll(false)
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.active && root.formMode === "" && !root.busy
        onTriggered: root.refreshAll(false)
    }

    // ── Processes ──────────────────────────────────────────────────────────
    Process {
        id: radioProc
        property string buffer: ""
        command: ["nmcli", "radio", "wifi"]
        stdout: SplitParser {
            onRead: line => radioProc.buffer += line + "\n"
        }
        onExited: code => {
            if (code === 0)
                root.wifiEnabled = radioProc.buffer.trim() === "enabled";
            radioProc.buffer = "";
            if (root.active && root.wifiEnabled && !scanProc.running) {
                scanProc.buffer = "";
                scanProc.command = ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY,SIGNAL,BSSID,DEVICE", "device", "wifi", "list", "--rescan", "no"];
                scanProc.running = true;
            } else if (!root.wifiEnabled) {
                root.wifiNetworks = [];
            }
        }
    }

    Process {
        id: statusProc
        property string buffer: ""
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION,DEVICE", "device", "status"]
        stdout: SplitParser {
            onRead: line => statusProc.buffer += line + "\n"
        }
        onExited: code => {
            if (code !== 0) {
                statusProc.buffer = "";
                return;
            }
            const rows = root.parseNmcli(statusProc.buffer);
            let ethState = "Unavailable"
            let ethConn = "";
            let ethDev = "";
            let wifiDev = "";
            let active = "";
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                const type = r[0] || "";
                const state = r[1] || "";
                const conn = r[2] || "";
                const dev = r[3] || "";
                if (type === "ethernet") {
                    if (state === "connected") {
                        ethState = "Connected";
                        ethConn = (conn && conn !== "--") ? conn : dev;
                        ethDev = dev;
                    } else if (ethState !== "Connected") {
                        ethState = state === "unavailable" ? "Unavailable" : "Disconnected";
                        ethConn = dev || ethConn;
                        if (!ethDev)
                            ethDev = dev;
                    }
                } else if (type === "wifi") {
                    wifiDev = dev;
                    if (state === "connected") {
                        active = (conn && conn !== "--") ? conn : "";
                    }
                }
            }
            const ethChanged = root.ethernetDevice !== ethDev;
            root.ethernetState = ethState;
            root.ethernetConnection = ethConn;
            root.ethernetDevice = ethDev;
            root.hasWifiDevice = wifiDev !== "";
            root.wifiDevice = wifiDev;
            root.activeWifi = active;
            statusProc.buffer = "";

            if (ethDev) {
                if (ethChanged || root.ethernetIp4 === "") {
                    ethDetailProc.buffer = "";
                    ethDetailProc.command = ["nmcli", "-t", "device", "show", ethDev];
                    if (!ethDetailProc.running)
                        ethDetailProc.running = true;
                }
            } else {
                root.ethernetMac = "";
                root.ethernetSpeed = "";
                root.ethernetIp4 = "";
                root.ethernetGateway4 = "";
                root.ethernetDns = "";
                root.ethernetIp6 = "";
                root.ethernetDetailsExpanded = false;
            }
        }
    }

    Process {
        id: savedProc
        property string buffer: ""
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: SplitParser {
            onRead: line => savedProc.buffer += line + "\n"
        }
        onExited: code => {
            if (code !== 0) {
                savedProc.buffer = "";
                return;
            }
            const rows = root.parseNmcli(savedProc.buffer);
            const map = {};
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                if ((r[1] || "") === "802-11-wireless" && r[0])
                    map[r[0]] = true;
            }
            root.savedWifi = map;
            savedProc.buffer = "";
        }
    }

    Process {
        id: scanProc
        property string buffer: ""
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY,SIGNAL,BSSID,DEVICE", "device", "wifi", "list", "--rescan", "no"]
        stdout: SplitParser {
            onRead: line => scanProc.buffer += line + "\n"
        }
        onExited: code => {
            root.scanning = false;
            if (code !== 0) {
                scanProc.buffer = "";
                return;
            }
            const rows = root.parseNmcli(scanProc.buffer);
            const bySsid = {};
            const list = [];
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                const inUse = (r[0] || "").trim() === "*";
                const ssid = r[1] || "";
                const security = r[2] || "";
                const signal = parseInt(r[3] || "0", 10) || 0;
                const bssid = r[4] || "";
                const device = r[5] || root.wifiDevice;
                if (!ssid)
                    continue;
                const item = {
                    ssid: ssid,
                    security: security,
                    signal: signal,
                    bssid: bssid,
                    device: device,
                    connected: inUse,
                    saved: !!root.savedWifi[ssid]
                };
                const prev = bySsid[ssid];
                if (!prev) {
                    bySsid[ssid] = item;
                    list.push(item);
                } else {
                    if (item.connected || (!prev.connected && item.signal > prev.signal)) {
                        bySsid[ssid] = item;
                        const idx = list.indexOf(prev);
                        if (idx >= 0)
                            list[idx] = item;
                    }
                }
            }
            // refresh saved flags against latest map
            for (let j = 0; j < list.length; j++)
                list[j].saved = !!root.savedWifi[list[j].ssid] || list[j].connected;
            list.sort((a, b) => {
                if (a.connected !== b.connected) return a.connected ? -1 : 1;
                if (a.saved !== b.saved) return a.saved ? -1 : 1;
                return b.signal - a.signal;
            });
            root.wifiNetworks = list;
            scanProc.buffer = "";
        }
    }

    Process {
        id: actionProc
        property string buffer: ""
        stdout: SplitParser { onRead: line => actionProc.buffer += line + "\n" }
        stderr: SplitParser { onRead: line => actionProc.buffer += line + "\n" }
        onExited: code => {
            root.busy = false;
            if (code !== 0)
                root.lastError = actionProc.buffer.trim() || "Action failed"
            actionProc.buffer = "";
            root.refreshAll(false);
        }
    }

    Process {
        id: formProc
        property string buffer: ""
        stdout: SplitParser { onRead: line => formProc.buffer += line + "\n" }
        stderr: SplitParser { onRead: line => formProc.buffer += line + "\n" }
        onExited: code => {
            root.formBusy = false;
            if (code === 0) {
                root.resetRequested();
                root.refreshAll(false);
            } else {
                root.formError = formProc.buffer.trim() || "Failed to connect";
            }
            formProc.buffer = "";
        }
    }

    Process {
        id: ethDetailProc
        property string buffer: ""
        command: ["nmcli", "-t", "device", "show"]
        stdout: SplitParser { onRead: line => ethDetailProc.buffer += line + "\n" }
        onExited: code => {
            if (code !== 0) {
                ethDetailProc.buffer = "";
                return;
            }
            const lines = ethDetailProc.buffer.split("\n");
            let mac = "", speed = "", carrier = "", ip4 = "", gw4 = "";
            let dns = [], ip6 = [];
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                if (!line) continue;
                const idx = line.indexOf(":");
                if (idx < 0) continue;
                const key = line.slice(0, idx);
                const val = line.slice(idx + 1);
                if (key === "GENERAL.HWADDR") mac = val;
                else if (key === "ETHERNET.SPEED") speed = val;
                else if (key === "WIRED-PROPERTIES.CARRIER") carrier = val;
                else if (key.indexOf("IP4.ADDRESS") === 0 && !ip4) ip4 = val;
                else if (key === "IP4.GATEWAY" && val && val !== "--") gw4 = val;
                else if (key.indexOf("IP4.DNS") === 0 && val) dns.push(val);
                else if (key.indexOf("IP6.ADDRESS") === 0 && ip6.length < 1 && val) ip6.push(val);
            }
            root.ethernetMac = mac;
            if (speed && speed !== "unknown")
                root.ethernetSpeed = speed + " Mb/s" + (carrier ? " · carrier: " + carrier : "");
            else if (carrier)
                root.ethernetSpeed = "carrier: " + carrier;
            else
                root.ethernetSpeed = "";
            root.ethernetIp4 = ip4;
            root.ethernetGateway4 = gw4;
            root.ethernetDns = dns.join(", ");
            root.ethernetIp6 = ip6.join(", ");
            ethDetailProc.buffer = "";
        }
    }
}
