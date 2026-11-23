import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../services"
import "../../theme"
import "media"

// One persisted notification in the center panel: compact app/summary/body
// rows built from the history entry, plus its own delete button.
Surface {
    id: root

    required property var modelData

    // Driven by the notification center's open state: the marquee must not keep
    // scrolling while the sheet is hidden.
    property bool animationActive: true

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

    readonly property string timeText: {
        const ms = Number(modelData.time) || 0;
        if (!ms)
            return "";

        const date = new Date(ms);
        if (date.toDateString() === new Date().toDateString())
            return Qt.formatDateTime(date, "HH:mm:ss");

        return Qt.formatDateTime(date, "dd MMM HH:mm:ss");
    }

    implicitHeight: content.implicitHeight + 12

    // Same flat filled surface as the DND row in the center panel: no accent
    // outline, urgency reads through the app-name colour only.
    radius: Dimensions.radius.medium
    surfaceColor: Colors.surfaceContainerHigh
    borderWidth: 0

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
                onClicked: NotificationService.remove(root.modelData.key)
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
    }
}
