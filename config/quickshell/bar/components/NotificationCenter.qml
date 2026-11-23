pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services"
import "../../theme"

// Notification center sheet for the bar bell. Like the night-light and sound
// sheets it grows out of the bar strip through EmbeddedSheet (mirrored to the
// right edge) and closes with Escape or an outside click. It shows the
// persisted history (newest first) in a framed list, per-entry delete buttons,
// a clear-all action and the do-not-disturb switch backed by
// NotificationService.
EmbeddedSheet {
    id: root

    mirror: true

    readonly property int actionSpacing: 10
    readonly property int listSpacing: 2
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    panelHeight: Math.min(560, root.maxPanelHeight)

    readonly property string statusText: {
        const total = NotificationService.history.count;
        if (total === 0)
            return "No notifications";

        const label = total + (total === 1 ? " notification" : " notifications");
        return total >= NotificationService.maxHistory
            ? label + " · showing last " + NotificationService.maxHistory
            : label;
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
        // Same title/status block as the night-light and sound sheets; the
        // do-not-disturb switch lives in the card below, while the clear
        // action moves up here so the list can use the whole panel height.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

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
                    color: NotificationService.dnd
                        ? Colors.primary
                        : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight

                    Behavior on color {
                        ColorAnimation { duration: Motion.color }
                    }
                }
            }

            Pill {
                id: clearAllPill

                Layout.alignment: Qt.AlignVCenter
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

        // ── Do not disturb card ──────────────────────────────────────────
        // Styled like the blue-light filter row in the night-light sheet.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: dndRow.implicitHeight + 24
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: NotificationService.dnd
                ? Colors.withAlpha(Colors.primary, 0.35)
                : Colors.withAlpha(Colors.outlineVariant, 0.22)

            Behavior on border.color { ColorAnimation { duration: Motion.hover } }

            RowLayout {
                id: dndRow

                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter
                    radius: Dimensions.radius.small + 2
                    color: NotificationService.dnd
                        ? Colors.primaryContainer
                        : Colors.surfaceContainerHighest

                    Behavior on color { ColorAnimation { duration: Motion.color } }

                    Text {
                        anchors.centerIn: parent
                        text: NotificationService.dnd
                            ? Icons.notificationsOff
                            : Icons.notifications
                        color: NotificationService.dnd
                            ? Colors.onPrimaryContainer
                            : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.large

                        Behavior on color { ColorAnimation { duration: Motion.color } }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: "Do not disturb"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: NotificationService.dnd
                            ? "Live popups and chimes are silenced"
                            : "Silence live popups and chimes"
                        color: NotificationService.dnd
                            ? Colors.primary
                            : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight

                        Behavior on color {
                            ColorAnimation { duration: Motion.color }
                        }
                    }
                }

                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    checked: NotificationService.dnd
                    onToggled: checked => NotificationService.setDnd(checked)
                }
            }
        }

        // ── History list ─────────────────────────────────────────────────
        // One framed list, like the device lists in the sound sheet, instead
        // of free-floating cards over the sheet background.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Dimensions.radius.medium
            color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
            clip: true

            // A ListView keeps only the delegates around the viewport alive.
            // The Repeater built every card the moment the sheet opened, and an
            // animating marquee costs ~2 % CPU per card, so a long history paid
            // for all fifty at once.
            ListView {
                id: listFlick

                anchors.fill: parent
                anchors.margins: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: root.listSpacing
                // A row is ~58 px, so 120 px keeps two rows of slack above
                // and below the viewport. A wheel notch or a keyboard scroll
                // then lands on ready delegates instead of flashing an empty
                // row, while only a handful of rows exist at once.
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
    }
}

