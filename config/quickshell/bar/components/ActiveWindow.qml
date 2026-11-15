import "../../theme"
import Quickshell.Hyprland
import QtQuick

// Active window chip: app icon + title in an M3 tonal pill.
Surface {
    id: root

    readonly property var client: {
        if (Hyprland.activeToplevel)
            return Hyprland.activeToplevel;
        // Quickshell 0.3.2 starts with activeToplevel == null until the first
        // focus event. Fall back to the last focused window on the current
        // workspace so the chip is populated right after startup.
        const workspace = Hyprland.focusedWorkspace?.id;
        return Hyprland.toplevels.values.find(t => t.workspace?.id === workspace && t.lastIpcObject?.focusHistoryID === 0)
            ?? Hyprland.toplevels.values.find(t => t.activated)
            ?? null;
    }
    readonly property string appClass: client
        ? (client.wayland?.appId ?? client.lastIpcObject?.class ?? "")
        : ""
    readonly property string title: client
        ? (client.title !== "" ? client.title : root.appClass)
        : ""

    visible: client !== null
    implicitWidth: 190
    implicitHeight: Dimensions.control.height
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 6

        AppIcon {
            id: appIcon
            appClass: root.appClass
            iconSize: Dimensions.icon.medium
            anchors.verticalCenter: parent.verticalCenter
            visible: ready
        }

        Text {
            width: parent.width - (appIcon.visible ? appIcon.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
            elide: Text.ElideRight
        }
    }
}
