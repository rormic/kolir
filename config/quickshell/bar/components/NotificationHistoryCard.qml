pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../services"
import "../../theme"
import "media"

// One persisted notification in the center panel: compact app/summary/body
// rows built from the history entry, plus its own delete button. It is a flat
// row inside the panel's framed list (like the sound sheet's device rows),
// not a card of its own.
Item {
    id: root

    required property var modelData

    // Driven by the notification center's open state: the marquee must not keep
    // scrolling while the sheet is hidden.
    property bool animationActive: true

    // A group is a run of adjacent history entries from one app, newest first:
    // modelData is the newest entry, `group` holds the whole run. Only the
    // first entry of a run is laid out; the rest are folded in here and get no
    // row of their own.
    property var group: []
    property bool leader: true
    property bool expanded: false
    // Vertical gap owned by the row, because the list spacing is zero so
    // folded-in entries cannot leave holes behind.
    property int listGap: 0

    signal toggleGroup()

    readonly property bool grouped: root.group.length > 1

    readonly property bool hasAppIcon: !!modelData.appIcon
        && String(modelData.appIcon).length > 0

    readonly property bool isCritical: modelData.urgency === NotificationUrgency.Critical

    // Same QIcon rule as AppIcon: a 14 px request decodes the 16 px PNG, so ask
    // for twice the drawn size and let Image downscale it.
    readonly property int appIconPixels: Math.max(2, Math.round(14 * Screen.devicePixelRatio * 2))

    readonly property color accent: root.isCritical
        ? Colors.error
        : modelData.urgency === NotificationUrgency.Low
            ? Colors.onSurfaceVariant
            : Colors.primary

    function timeTextFor(ms) {
        const value = Number(ms) || 0;
        if (!value)
            return "";

        const date = new Date(value);
        if (date.toDateString() === new Date().toDateString())
            return Qt.formatDateTime(date, "HH:mm:ss");

        return Qt.formatDateTime(date, "dd MMM HH:mm:ss");
    }

    readonly property string timeText: root.timeTextFor(modelData.time)

    // The newest entry's trash drops the whole run it leads; older entries
    // inside an expanded run keep their own trash and remove one entry.
    function removeGroup() {
        // Snapshot the keys first: the group is rebuilt from the history model
        // and the entries behind it can go away after the first removal.
        const keys = [];
        for (let i = 0; i < root.group.length; i++)
            keys.push(root.group[i].key);
        for (let i = 0; i < keys.length; i++)
            NotificationService.remove(keys[i]);
    }

    implicitHeight: content.implicitHeight + 12

    visible: root.leader
    height: root.leader ? root.implicitHeight + root.listGap : 0

    // Expanding a run reveals the older rows instead of popping them in; the
    // row clips so the list below never sees the new content early.
    clip: true

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Motion.move
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler { id: rowHover }

    // Hover tint only; the row keeps the list container's fill so urgency
    // reads through the app-name colour alone.
    Rectangle {
        anchors.fill: parent
        radius: Dimensions.radius.small
        color: rowHover.hovered
            ? Colors.stateLayer(Colors.onSurface, 0.06)
            : "transparent"

        Behavior on color { ColorAnimation { duration: Motion.fade } }
    }

    Column {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 6
        }
        spacing: 2

        // Header: app icon, sender, summary, time and the delete action.
        RowLayout {
            width: parent.width
            spacing: 6

            Image {
                id: appIcon

                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasAppIcon && status === Image.Ready
                source: !root.hasAppIcon
                    ? ""
                    : (root.modelData.appIcon.startsWith("/")
                        ? root.modelData.appIcon
                        : Quickshell.iconPath(root.modelData.appIcon,
                            "application-x-executable"))
                sourceSize: Qt.size(root.appIconPixels, root.appIconPixels)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            // Fallback when the sender has no icon: a generic app glyph keeps
            // every row aligned and colored by urgency.
            Text {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                visible: !root.hasAppIcon || appIcon.status !== Image.Ready
                text: Icons.apps
                color: root.accent
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.small
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                // The sender is a prefix on the same line as the summary, not
                // a row of its own; cap it so long names cannot eat the title.
                Layout.maximumWidth: Math.max(48, parent.width * 0.32)
                text: root.modelData.appName
                color: root.accent
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelLarge
                font.weight: Typography.weight.bold
                elide: Text.ElideRight
            }

            // The same quiet "N ⌄" control as the live card. It sits beside the
            // app name so the newest run reads as "Telegram, 3 messages".
            Item {
                id: countControl

                Layout.alignment: Qt.AlignVCenter
                visible: root.grouped
                implicitWidth: countRow.implicitWidth + 12
                implicitHeight: 20

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: countHover.hovered
                        ? Colors.stateLayer(Colors.onSurface, 0.08)
                        : "transparent"

                    Behavior on color { ColorAnimation { duration: Motion.fade } }
                }

                Row {
                    id: countRow

                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.group.length
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: Typography.weight.medium
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.expanded ? Icons.chevronUp : Icons.chevronDown
                        color: Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.small
                    }
                }

                HoverHandler {
                    id: countHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.toggleGroup()
                }
            }

            // Long titles scroll like the now-playing track name instead of
            // wrapping or clipping; short ones sit still.
            MarqueeText {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                visible: root.modelData.summary !== ""
                active: root.animationActive
                text: root.modelData.summary
                textColor: Colors.onSurface
                textSize: Typography.size.titleSmall
                textWeight: Typography.weight.bold
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.timeText
                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.75)
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
            }

            IconButton {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter
                icon: Icons.trash
                iconSize: Dimensions.icon.medium
                iconColor: Colors.onSurfaceVariant
                containerColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.6)
                onClicked: {
                    if (root.grouped)
                        root.removeGroup();
                    else
                        NotificationService.remove(root.modelData.key);
                }
            }
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: root.modelData.body
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            maximumLineCount: 1
            elide: Text.ElideRight
        }

        // The rest of the run, newest first. Each row keeps its own time and
        // trash; the header's trash drops the whole run.
        Rectangle {
            width: parent.width
            height: 1
            visible: root.grouped && root.expanded
            color: Colors.withAlpha(Colors.outlineVariant, 0.18)
        }

        Column {
            id: olderList

            width: parent.width
            spacing: 4
            visible: root.grouped && root.expanded

            Repeater {
                model: root.grouped && root.expanded ? root.group.slice(1) : []

                delegate: Item {
                    id: olderRow

                    required property var modelData

                    width: olderList.width
                    implicitHeight: olderContent.implicitHeight + 6

                    Column {
                        id: olderContent

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            topMargin: 3
                        }
                        spacing: 2

                        RowLayout {
                            width: parent.width
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: olderRow.modelData.summary
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.titleSmall
                                font.weight: Typography.weight.bold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: root.timeTextFor(olderRow.modelData.time)
                                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.75)
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                            }

                            IconButton {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignVCenter
                                icon: Icons.trash
                                iconSize: Dimensions.icon.small
                                iconColor: Colors.onSurfaceVariant
                                containerColor: "transparent"
                                onClicked: NotificationService.remove(olderRow.modelData.key)
                            }
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: olderRow.modelData.body
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            wrapMode: Text.Wrap
                            textFormat: Text.StyledText
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
