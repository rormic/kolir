import "../theme"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
    id: root

    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        keepOnReload: true

        onNotification: n => {
            n.tracked = true
        }
    }

    PanelWindow {
        id: win
        visible: server.trackedNotifications.values.length > 0
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
                model: server.trackedNotifications

                delegate: NotificationCard {
                    width: col.width
                }
            }
        }
    }
}
