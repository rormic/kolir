import QtQuick
import "../../services"
import "../../theme"

// Active-tunnel capsule.
//
// A control, not a status: it names the tunnel that is up (a WireGuard/OpenVPN
// profile through NetworkManager, or "Tailscale" when only the mesh is
// connected) and a left click opens Settings → Internet, the page that owns
// both. It therefore sits in the status zone next to the Bluetooth capsule,
// next to the other device and session readouts rather than in the
// brightness/volume control row.
//
// The capsule only exists while a tunnel is really up; a machine with no VPN
// configured and no Tailscale login keeps the bar unchanged. The primary tint
// marks a live session state, not a warning.
Pill {
    id: root

    signal activated()

    // Bound by Bar to the settings sheet's Internet page.
    property bool popupActive: false

    visible: VpnService.connected || TailscaleService.connected

    icon: Icons.shield
    iconColor: Colors.primary
    text: VpnService.connected ? VpnService.activeName : "Tailscale"
    textMaxWidth: 140
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    spacing: 5
    active: root.popupActive

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
