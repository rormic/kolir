import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Workspace switcher: neon active indicator with layered glow.
Surface {
    id: root

    readonly property int cellWidth: 20
    readonly property int cellHeight: 22

    function toRoman(n) {
        const r = ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
        return r[n - 1] ?? String(n)
    }

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
                    if (!ws || !ws.toplevels) return null;
                    const tops = ws.toplevels.values;
                    return tops.length > 0 ? tops[0] : null;
                }
                readonly property string appClass: topApp
                    ? (topApp.wayland?.appId ?? topApp.lastIpcObject?.class ?? "")
                    : ""

                onIsFocusedChanged: { if (isFocused) bounceAnim.restart() }

                implicitWidth: root.cellWidth
                implicitHeight: root.cellHeight

                // Neon glow layer 1 (outermost, most diffuse)
                Rectangle {
                    visible: wsItem.isFocused
                    anchors.centerIn: parent
                    width: root.cellWidth + 8
                    height: root.cellHeight - 1
                    radius: height / 2
                    color: Colors.withAlpha(Colors.primary, 0.07)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                // Neon glow layer 2
                Rectangle {
                    visible: wsItem.isFocused
                    anchors.centerIn: parent
                    width: root.cellWidth + 2
                    height: root.cellHeight - 3
                    radius: height / 2
                    color: Colors.withAlpha(Colors.primary, 0.13)
                }

                // Main indicator
                Rectangle {
                    id: indicator
                    anchors.centerIn: parent
                    width: wsItem.isFocused ? root.cellWidth - 2 : root.cellWidth - 6
                    height: root.cellHeight - 4
                    radius: height / 2

                    color: wsItem.isFocused
                        ? Colors.withAlpha(Colors.primaryContainer, 0.85)
                        : wsMouse.containsMouse
                            ? Colors.stateLayer(Colors.onSurface, 0.08)
                            : "transparent"

                    // Neon border on active
                    border.width: wsItem.isFocused ? 1 : 0
                    border.color: Colors.withAlpha(Colors.primary, 0.7)

                    Behavior on width  { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 150; easing.type: Easing.OutCubic } }

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
                        text: root.toRoman(wsItem.wsId)
                        color: wsItem.isFocused ? Colors.primary : Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                        font.family: Typography.barFont
                        font.pixelSize: wsItem.wsId === 8 ? 8 : 9
                        font.weight: Typography.weight.bold
                    }

                    // Window presence dot
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: wsItem.hasWindow && appIcon.visible
                        width: 3; height: 3; radius: 1.5
                        color: wsItem.isFocused ? Colors.primary : Colors.withAlpha(Colors.outline, 0.6)
                    }
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`workspace ${wsItem.wsId}`)
                }

                SequentialAnimation {
                    id: bounceAnim
                    NumberAnimation { target: indicator; property: "scale"; to: 1.12; duration: 90;  easing.type: Easing.OutQuad }
                    NumberAnimation { target: indicator; property: "scale"; to: 1.0;  duration: 150; easing.type: Easing.OutBack }
                }
            }
        }
    }
}
