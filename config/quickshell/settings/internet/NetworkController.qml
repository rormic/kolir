import QtQuick

// nmcli-backed state for the Internet page. The page instantiates exactly one
// controller and binds its UI to these properties; ownership stays inside the
// page, so polling can follow page visibility.
Item {
    id: root

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
}
