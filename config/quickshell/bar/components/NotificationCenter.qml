pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services"
import "../../theme"

// Notification center sheet for the bar bell. Like the night-light and sound
// sheets it grows out of the bar strip through EmbeddedSheet (mirrored to the
// right edge) and closes with Escape or an outside click. It shows the
// persisted history (newest first), per-entry delete buttons, a clear-all
// action and the do-not-disturb switch backed by NotificationService.
EmbeddedSheet {
    id: root

    mirror: true

    readonly property int headerHeight: 52
    readonly property int actionSpacing: 10
    readonly property int listSpacing: 4
    readonly property int footerHeight: 40
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    panelHeight: Math.min(560, root.maxPanelHeight)

    readonly property string statusText: {
        const total = NotificationService.history.count;
        if (total === 0)
            return "No notifications";

        return total + (total === 1 ? " notification" : " notifications");
    }

    function scrollBy(dy) {
        const max = Math.max(0,
            listFlick.contentHeight - listFlick.height);
        listFlick.contentY = Math.max(0, Math.min(max,
            listFlick.contentY + dy));
    }

    function open() {
        if (root.opened)
            return;

        NotificationService.setPanelOpen(true);
        // Live popups would otherwise sit under the center sheet (and come
        // back when it closes); they are already in the history.
        NotificationService.suppressTracked();
        root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        root.revealClose();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    onDismissalRequested: root.close()

    onDidClose: NotificationService.setPanelOpen(false)

    Keys.onEscapePressed: function (event) {
        root.close();
        event.accepted = true;
    }

    Keys.onUpPressed: function (event) {
        root.scrollBy(-54);
        event.accepted = true;
    }

    Keys.onDownPressed: function (event) {
        root.scrollBy(54);
        event.accepted = true;
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_PageUp) {
            root.scrollBy(-listFlick.height * 0.8);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root.scrollBy(listFlick.height * 0.8);
            event.accepted = true;
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function clear(): void {
            NotificationService.clear();
        }

        function setDnd(enabled: bool): void {
            NotificationService.setDnd(enabled);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + 14
            leftMargin: 14
            rightMargin: 14
            bottomMargin: 14
        }
        spacing: root.actionSpacing

        // ── Header ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight

            // Square header button: the bell is the do-not-disturb switch, in
            // the same flat rounded-square style as the other header icons.
            Rectangle {
                id: dndButton

                width: 38
                height: 38
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                radius: Dimensions.radius.small + 2
                color: NotificationService.dnd
                    ? Colors.errorContainer
                    : Colors.withAlpha(Colors.primary, 0.11)
                border.width: 1
                border.color: NotificationService.dnd
                    ? Colors.errorContainer
                    : Colors.withAlpha(Colors.primary, 0.45)

                Behavior on color {
                    ColorAnimation { duration: Motion.color }
                }

                StateLayer {
                    shown: dndButtonMouse.containsMouse && !NotificationService.dnd
                    tint: Colors.onSurface
                    strength: 0.08
                }

                Text {
                    anchors.centerIn: parent
                    text: NotificationService.dnd
                        ? Icons.notificationsOff
                        : Icons.notifications
                    color: NotificationService.dnd
                        ? Colors.onErrorContainer
                        : Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.large

                    Behavior on color {
                        ColorAnimation { duration: Motion.color }
                    }
                }

                MouseArea {
                    id: dndButtonMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.setDnd(!NotificationService.dnd)
                }
            }

            ColumnLayout {
                anchors {
                    left: parent.left
                    leftMargin: 50
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.titleLarge
                    font.weight: Typography.weight.bold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }
        }

        // ── History list ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // A ListView keeps only the delegates around the viewport alive.
            // The Repeater built every card the moment the sheet opened, and an
            // animating marquee costs ~2 % CPU per card, so a long history paid
            // for all fifty at once.
            ListView {
                id: listFlick

                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: root.listSpacing
                // A card is ~60 px (30 px header row + one body line + 12 px
                // padding), so 120 px keeps two card heights of slack above
                // and below the viewport. A wheel notch or a keyboard scroll
                // then lands on ready delegates instead of flashing an empty
                // row, while only a handful of cards exist at once.
                cacheBuffer: 120
                model: NotificationService.history

                delegate: NotificationHistoryCard {
                    width: ListView.view.width
                    // `modal` stays true through the close animation, so
                    // the marquee does not freeze mid-slide.
                    animationActive: root.modal
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: NotificationService.history.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Icons.notificationsNone
                    color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                    font.family: Typography.iconFont
                    font.pixelSize: 28
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications yet"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight

            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 1
                color: Colors.withAlpha(Colors.outlineVariant, 0.2)
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 2
                    verticalCenter: parent.verticalCenter
                }
                text: NotificationService.history.count >= NotificationService.maxHistory
                    ? "Showing last " + NotificationService.maxHistory
                    : ""
                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }

            Pill {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                icon: Icons.trash
                iconSize: Dimensions.icon.medium
                iconColor: Colors.onSurfaceVariant
                text: "Clear all"
                textSize: Typography.size.labelMedium
                textWeight: Typography.weight.medium
                horizontalPadding: Dimensions.padding.chipHorizontal + 2
                opacity: NotificationService.history.count === 0 ? 0.5 : 1.0

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: NotificationService.history.count > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.clear()
                }
            }
        }
    }
}
