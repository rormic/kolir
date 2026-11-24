pragma ComponentBehavior: Bound

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
            // The gap lives inside each slot (see baseHeight) so it collapses
            // together with the card instead of leaving a 8 px step behind.
            spacing: 0

            Repeater {
                model: NotificationService.server.trackedNotifications

                delegate: Item {
                    id: slot

                    required property Notification modelData
                    required property int index

                    readonly property real baseHeight: card.implicitHeight + 8

                    width: col.width
                    height: baseHeight * (1 - card.closeProgress)
                    clip: true

                    NotificationCard {
                        id: card

                        width: parent.width
                        anchors.top: parent.top
                        modelData: slot.modelData
                        index: slot.index

                        onCloseStarted: exitAnim.start()
                    }

                    // The card fades over Motion.listExit; the height starts a
                    // little later, when the card is already almost invisible,
                    // so the clipped collapse never reads as a squash.
                    SequentialAnimation {
                        id: exitAnim

                        PauseAnimation {
                            duration: 100
                        }
                        NumberAnimation {
                            target: card
                            property: "closeProgress"
                            to: 1
                            duration: Motion.move
                            easing.type: Easing.OutCubic
                        }

                        onFinished: card.commitClose()
                    }
                }
            }
        }
    }
}
