import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Workspace switcher: one neon highlight travels between the cells, so a
// switch reads as movement instead of ten independent fades.
Surface {
    id: root

    readonly property int cellWidth: 20
    readonly property int cellHeight: 22
    // The bar shows exactly ten workspaces; Hyprland IDs above that keep the
    // pill empty instead of pushing the row wider.
    readonly property int visibleWorkspaces: 10
    readonly property int focusedIndex: {
        const id = Hyprland.focusedWorkspace?.id ?? 0
        return id >= 1 && id <= root.visibleWorkspaces ? id - 1 : -1
    }

    // Skip the arrival pulse on the first focus after a shell start, when the
    // highlight simply appears in place.
    property bool settledOnce: false
    // Last workspace the bar could show. IDs above `visibleWorkspaces` hide the
    // highlight without dragging it back to the first cell, so returning to a
    // visible workspace does not fly in from the left edge.
    property int lastIndex: 0
    // The initial placement must not animate; only later switches travel.
    property bool travelReady: false

    function toRoman(n) {
        const r = ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
        return r[n - 1] ?? String(n)
    }

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // A small squash when the highlight lands, so the end of the travel is
    // felt rather than just stopped.
    SequentialAnimation {
        id: arrival
        NumberAnimation { target: thumb; property: "scale"; to: 1.06; duration: 70;  easing.type: Easing.OutQuad }
        NumberAnimation { target: thumb; property: "scale"; to: 1.0;  duration: 150; easing.type: Easing.OutCubic }
    }

    onFocusedIndexChanged: {
        if (focusedIndex < 0)
            return
        if (settledOnce)
            arrival.restart()
        settledOnce = true
        lastIndex = focusedIndex
    }

    // If the shell starts with a workspace already focused, place the highlight
    // there without travel or a pulse; a later arrival (focus read after
    // startup) is treated as an appearance as well.
    Component.onCompleted: {
        if (focusedIndex >= 0) {
            lastIndex = focusedIndex
            settledOnce = true
        }
        travelReady = true
    }

    Item {
        id: cells
        anchors.centerIn: parent
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        // The single indicator. Declared before the row so icons and numerals
        // stay on top while the highlight passes underneath them.
        Item {
            id: thumb

            x: root.lastIndex * root.cellWidth + 1
            y: (cells.height - height) / 2
            width: root.cellWidth - 2
            height: root.cellHeight - 4
            visible: root.focusedIndex >= 0

            Behavior on x {
                enabled: root.travelReady
                NumberAnimation {
                    duration: Motion.workspace
                    easing.type: Easing.OutQuint
                }
            }

            // Neon glow layer 1 (outermost, most diffuse)
            Rectangle {
                anchors.centerIn: parent
                width: root.cellWidth + 8
                height: root.cellHeight - 1
                radius: height / 2
                color: Colors.withAlpha(Colors.primary, 0.07)
            }

            // Neon glow layer 2
            Rectangle {
                anchors.centerIn: parent
                width: root.cellWidth + 2
                height: root.cellHeight - 3
                radius: height / 2
                color: Colors.withAlpha(Colors.primary, 0.13)
            }

            // Main indicator
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.withAlpha(Colors.primaryContainer, 0.85)
                border.width: 1
                border.color: Colors.withAlpha(Colors.primary, 0.7)
            }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 0

            Repeater {
                model: root.visibleWorkspaces
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

                    implicitWidth: root.cellWidth
                    implicitHeight: root.cellHeight

                    // Hover tint of the cell itself, independent of the
                    // travelling highlight.
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"

                        StateLayer {
                            shown: wsMouse.containsMouse && !wsItem.isFocused
                            tint: Colors.onSurface
                            strength: 0.08
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

                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Hyprland runs a Lua config, so `hyprctl dispatch` parses
                        // its argument as Lua (`return hl.dispatch(<arg>)`); the
                        // legacy `workspace N` string is a syntax error there.
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${wsItem.wsId} })`)
                    }
                }
            }
        }
    }
}
