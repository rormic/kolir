import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../theme"
import "../bar/components"
import "internet"

// Internet management page shown inside the settings popup. Uses nmcli
// (NetworkManager) for Wi-Fi control and to report Ethernet status.
Item {
    id: root

    signal back()

    property int topInset: 0

    implicitWidth: 380
    implicitHeight: 520

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

    function resetForms() {
        formMode = "";
        formNetwork = null;
        formSsid = "";
        formPassword = "";
        formShowPassword = false;
        formBusy = false;
        formError = "";
        formSecurityIndex = 1;
    }

    function signalIcon(signal) {
        const s = Number(signal) || 0;
        if (s <= 0) return Icons.signalWifi0;
        if (s < 30) return Icons.signalWifi1;
        if (s < 55) return Icons.signalWifi2;
        if (s < 80) return Icons.signalWifi3;
        return Icons.signalWifi4;
    }

    function securityLabel(sec) {
        if (!sec || sec === "" || sec === "--")
            return "Open";
        return sec;
    }

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
    onVisibleChanged: {
        if (visible) {
            refreshDelay.restart();
        } else {
            refreshDelay.stop();
            resetForms();
        }
    }

    // Defer the first nmcli refresh until the page transition has finished,
    // so process startup doesn't compete with animation frames.
    Timer {
        id: refreshDelay
        interval: 200
        onTriggered: if (root.visible) root.refreshAll(false)
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.visible && root.formMode === "" && !root.busy
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
            if (root.visible && root.wifiEnabled && !scanProc.running) {
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
                root.resetForms();
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

    // ── Header ─────────────────────────────────────────────────────────────
    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Internet"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 10

            // Ethernet status
            EthernetCard {
                state: root.ethernetState
                connection: root.ethernetConnection
                device: root.ethernetDevice
                mac: root.ethernetMac
                speed: root.ethernetSpeed
                ip4: root.ethernetIp4
                gateway4: root.ethernetGateway4
                dns: root.ethernetDns
                ip6: root.ethernetIp6
                expanded: root.ethernetDetailsExpanded
                onToggleExpanded: root.ethernetDetailsExpanded = !root.ethernetDetailsExpanded
            }

            // Wi-Fi adapter card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wifiCard.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: wifiCard
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: Dimensions.radius.small + 2
                            color: root.wifiEnabled ? Colors.primaryContainer : Colors.surfaceContainerHighest
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiEnabled ? Icons.wifi : Icons.wifiOff
                                color: root.wifiEnabled ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.large
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: "Wi-Fi"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (!root.hasWifiDevice) return "No adapter found";
                                    if (!root.wifiEnabled) return "Disabled";
                                    if (root.activeWifi) return "Connected · " + root.activeWifi;
                                    return "Enabled";
                                }
                                color: root.wifiConnected ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: root.wifiEnabled
                            interactive: root.hasWifiDevice
                            onToggled: value => {
                                actionProc.buffer = "";
                                actionProc.command = ["nmcli", "radio", "wifi", value ? "on" : "off"];
                                actionProc.running = true;
                                root.busy = true;
                                if (!value) root.resetForms();
                            }
                        }
                    }

                    Text {
                        visible: root.lastError !== ""
                        Layout.fillWidth: true
                        text: root.lastError
                        color: Colors.error
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Actions row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.hasWifiDevice

                Rectangle {
                    id: scanBtn
                    property bool hovered: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.full
                    color: scanBtn.hovered ? Colors.stateLayer(Colors.primary, 0.16) : Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: scanBtn.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: root.wifiEnabled ? 1.0 : 0.5
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            id: scanIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.refresh
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                            RotationAnimation on rotation {
                                from: 0; to: 360; duration: 1000
                                loops: Animation.Infinite
                                running: root.scanning
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.scanning ? "Scanning…" : "Refresh"
                            color: scanBtn.hovered ? Colors.primary : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.medium
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.wifiEnabled
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: scanBtn.hovered = containsMouse
                        onClicked: root.refreshAll(true)
                    }
                }

                Rectangle {
                    id: hiddenBtn
                    property bool hovered: false
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Dimensions.radius.full
                    color: hiddenBtn.hovered ? Colors.stateLayer(Colors.primary, 0.16) : Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: hiddenBtn.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.22)
                    opacity: root.wifiEnabled ? 1.0 : 0.5
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.add
                        color: hiddenBtn.hovered ? Colors.primary : Colors.onSurface
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.wifiEnabled
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: hiddenBtn.hovered = containsMouse
                        onClicked: {
                            root.formMode = root.formMode === "hidden" ? "" : "hidden";
                            root.formNetwork = null;
                            root.formSsid = "";
                            root.formPassword = "";
                            root.formShowPassword = false;
                            root.formError = "";
                            root.formSecurityIndex = 1;
                        }
                    }
                }
            }

            // Connection form (password or hidden network)
            WifiConnectionForm {
                mode: root.formMode
                visible: root.formMode === "hidden"
                    || (root.formMode === "password" && root.formNetwork !== null)
                ssid: root.formMode === "password"
                    ? (root.formNetwork ? root.formNetwork.ssid : "")
                    : root.formSsid
                showPassword: root.formShowPassword
                busy: root.formBusy
                error: root.formError
                securityIndex: root.formSecurityIndex
                onPasswordEdited: value => root.formPassword = value
                onSsidEdited: value => root.formSsid = value
                onShowPasswordToggled: root.formShowPassword = !root.formShowPassword
                onSecurityIndexSelected: index => root.formSecurityIndex = index
                onSubmitRequested: {
                    if (root.formMode === "password")
                        root.submitPasswordForm();
                    else if (root.formMode === "hidden")
                        root.submitHiddenForm();
                }
                onCancelRequested: root.resetForms()
            }

            // Networks header
            RowLayout {
                Layout.fillWidth: true
                visible: root.hasWifiDevice
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi networks"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }
                Text {
                    text: root.wifiNetworks.length + (root.wifiNetworks.length === 1 ? " network" : " networks")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
            }

            // Networks list
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                visible: root.hasWifiDevice
                radius: Dimensions.radius.medium
                color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
                clip: true

                ListView {
                    id: netList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.wifiNetworks

                    delegate: WifiNetworkRow {
                        required property var modelData

                        width: netList.width
                        network: modelData
                        savedMap: root.savedWifi
                        onConnectRequested: root.connectNetwork(modelData)
                        onForgetRequested: root.forgetNetwork(modelData)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: netList.count === 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.wifiEnabled ? Icons.wifi : Icons.wifiOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                        font.family: Typography.iconFont
                        font.pixelSize: 26
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !root.wifiEnabled ? "Wi-Fi is off" : "No networks found"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }
            }
        }
    }
}
