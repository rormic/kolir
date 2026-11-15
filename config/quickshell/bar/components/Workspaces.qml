import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"

// Workspace switcher with an M3 navigation-bar style active indicator.
Surface {
    id: root

    readonly property int cellWidth: 26
    readonly property int cellHeight: 24

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: 10

            delegate: Item {
                id: wsItem

                readonly property int wsId: index + 1
                readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
                readonly property bool hasWindow: ws ? (ws.toplevels ? ws.toplevels.values.length > 0 : false) : false
                readonly property bool isFocused: Hyprland.focusedWorkspace?.id === wsId

                readonly property var topApp: {
                    if (!ws || !ws.toplevels)
                        return null;
                    const tops = ws.toplevels.values;
                    return tops.length > 0 ? tops[0] : null;
                }
                readonly property string appClass: topApp
                    ? (topApp.wayland?.appId ?? topApp.lastIpcObject?.class ?? "")
                    : ""

                implicitWidth: root.cellWidth
                implicitHeight: root.cellHeight

                Rectangle {
                    id: indicator
                    anchors.centerIn: parent
                    width: wsItem.isFocused ? root.cellWidth : root.cellWidth - 4
                    height: root.cellHeight - 2
                    radius: height / 2
                    color: wsItem.isFocused
                        ? Colors.primaryContainer
                        : wsMouse.containsMouse
                            ? Colors.stateLayer(Colors.onSurface, 0.08)
                            : "transparent"

                    Behavior on width {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    AppIcon {
                        id: appIcon
                        anchors.centerIn: parent
                        appClass: wsItem.hasWindow ? wsItem.appClass : ""
                        iconSize: Dimensions.icon.medium
                        visible: wsItem.hasWindow && ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !wsItem.hasWindow || !appIcon.visible
                        text: wsItem.wsId
                        color: wsItem.isFocused
                            ? Colors.onPrimaryContainer
                            : Colors.withAlpha(Colors.onSurfaceVariant, 0.8)
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: Typography.weight.bold
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: wsItem.hasWindow && appIcon.visible
                        width: 3
                        height: 3
                        radius: 1.5
                        color: wsItem.isFocused ? Colors.primary : Colors.outline
                    }
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`workspace ${wsItem.wsId}`)
                }
            }
        }
    }
}
