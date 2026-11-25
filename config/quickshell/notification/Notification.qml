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
//
// Notifications that arrive one after another from the same app share a card:
// the first notification of a run owns the card and folds in every following
// notification with the same appName. A notification from another app in
// between starts a new card, so the stack keeps the arrival order.
Scope {
    id: root

    // trackedNotifications is oldest-first: a new arrival is appended.
    readonly property var tracked: NotificationService.server.trackedNotifications.values

    // All notifications folded into the card owned by the run at `index`.
    function groupAt(index) {
        const members = [];
        const first = root.tracked[index];
        if (!first)
            return members;

        members.push(first);
        for (let i = index + 1; i < root.tracked.length; i++) {
            const next = root.tracked[i];
            if (!next || next.appName !== first.appName)
                break;
            members.push(next);
        }

        return members;
    }

    // Only the first notification of a same-app run draws a card. The rest
    // stay tracked but are folded into it, so a hidden member never owns its
    // own timer or dismissal target.
    function isLeader(index) {
        if (index <= 0)
            return true;

        const current = root.tracked[index];
        const previous = root.tracked[index - 1];
        return !current || !previous || current.appName !== previous.appName;
    }

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

        // Keep the layer surface one fixed size while the cards fold. Hyprland
        // stretches the previous buffer to every intermediate surface size
        // when a layer shell is resized continuously, which makes the card
        // text look like it is changing font during the collapse. The cards
        // animate entirely inside this surface instead.
        readonly property int surfaceHeight: Math.max(126,
            (win.screen ? win.screen.height : 1440)
                - Dimensions.bar.height - Dimensions.bar.margin - 8)

        implicitWidth: 380
        implicitHeight: win.surfaceHeight

        // Only the cards are interactive; the transparent tail below the
        // stack stays click-through, like the bar's own mask.
        mask: Region {
            x: 0
            y: 0
            width: win.width
            height: Math.max(0, Math.min(col.implicitHeight, win.height))
        }

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

                    readonly property bool leader: root.isLeader(slot.index)
                    readonly property var group: slot.leader
                        ? root.groupAt(slot.index) : []
                    readonly property var cardItem: cardLoader.item
                    // A grouped card reserves room for its stack edges and
                    // keeps a normal gap before the next card starts.
                    readonly property real baseHeight: slot.cardItem
                        ? slot.cardItem.implicitHeight
                            + (slot.cardItem.count > 1 ? 16 : 8)
                        : 8
                    // The layer count mirrors the notifications folded behind
                    // the card; expanding the card takes the stack away.
                    readonly property int stackPages: slot.cardItem
                        ? Math.min(slot.cardItem.count - 1, 2) : 0
                    readonly property bool stacked: slot.leader && slot.cardItem
                        && slot.cardItem.count > 1

                    width: col.width
                    height: slot.leader
                        ? slot.baseHeight * (1 - (slot.cardItem
                            ? slot.cardItem.closeProgress : 0))
                        : 0
                    visible: slot.leader
                    clip: true

                    // Two quieter sheets peek out under the card, each 4 px
                    // lower and narrower, so a group reads as a stack without
                    // a shadow the shell does not use. The slot keeps a normal
                    // gap after them before the next card starts.
                    Rectangle {
                        visible: slot.stacked && slot.stackPages >= 2
                        x: 16
                        y: slot.cardItem ? slot.cardItem.height - 4 : 0
                        width: slot.width - 32
                        height: 12
                        radius: Dimensions.radius.large
                        color: Colors.withAlpha(Colors.surfaceContainerLow, 0.80)
                        border.width: 1
                        border.color: Colors.withAlpha(
                            slot.cardItem ? slot.cardItem.tint : Colors.primary, 0.28)
                        // The edges hug the card bottom and fade as the stack
                        // opens, so expanding never blinks them away.
                        opacity: slot.cardItem
                            ? slot.cardItem.opacity * (1 - slot.cardItem.fold) : 0
                        z: -2

                        TapHandler {
                            onTapped: if (slot.cardItem) slot.cardItem.expanded = true
                        }
                    }

                    Rectangle {
                        visible: slot.stacked && slot.stackPages >= 1
                        x: 8
                        y: slot.cardItem ? slot.cardItem.height - 4 : 0
                        width: slot.width - 16
                        height: 8
                        radius: Dimensions.radius.large
                        color: Colors.withAlpha(Colors.surfaceContainerLow, 0.80)
                        border.width: 1
                        border.color: Colors.withAlpha(
                            slot.cardItem ? slot.cardItem.tint : Colors.primary, 0.28)
                        opacity: slot.cardItem
                            ? slot.cardItem.opacity * (1 - slot.cardItem.fold) : 0
                        z: -1

                        TapHandler {
                            onTapped: if (slot.cardItem) slot.cardItem.expanded = true
                        }
                    }

                    // A folded-in notification contributes no item at all, so
                    // it cannot run an expiry timer of its own.
                    Loader {
                        id: cardLoader

                        active: slot.leader
                        width: parent.width
                        anchors.top: parent.top
                        sourceComponent: cardComponent
                    }

                    Component {
                        id: cardComponent

                        NotificationCard {
                            group: slot.group
                            index: slot.index

                            onCloseStarted: exitAnim.start()
                        }
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
                            target: slot.cardItem
                            property: "closeProgress"
                            to: 1
                            duration: Motion.move
                            easing.type: Easing.OutCubic
                        }

                        onFinished: if (slot.cardItem) slot.cardItem.commitClose()
                    }
                }
            }
        }
    }
}
