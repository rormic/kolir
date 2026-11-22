import "../theme"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Live notification card stack. The daemon and its history live in
// NotificationService; this surface only renders the notifications that are
// currently tracked and not silenced by do-not-disturb.
Scope {
    id: root

    PanelWindow {
        id: win
        visible: NotificationService.server.trackedNotifications.values.length > 0
            && !NotificationService.dnd
            && !NotificationService.panelOpen
        color: "transparent"

        anchors {
            top: true
            right: true
        }
        margins {
            top: Dimensions.bar.height + Dimensions.bar.margin + 8
            right: 12
        }

        implicitWidth: 380
        implicitHeight: col.implicitHeight

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"

        Column {
            id: col
            width: parent.width
            spacing: 8

            Repeater {
                model: NotificationService.server.trackedNotifications

                delegate: NotificationCard {
                    width: col.width
                }
            }
        }
    }
}
