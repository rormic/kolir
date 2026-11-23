pragma ComponentBehavior: Bound

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
    readonly property int pillWidth: cellWidth - 2
    readonly property int pillHeight: cellHeight - 4

    // One lookup table for all ten cells. Each delegate used to run its own
    // find() over a freshly materialised workspace array, so the ten cells
    // rescanned the list on every workspace/toplevel change.
    readonly property var workspaceById: {
        const map = ({})
        const values = Hyprland.workspaces.values

        for (let i = 0; i < values.length; i++) {
            const ws = values[i]
            // First match wins, exactly like the find() this replaces.
            if (ws.id >= 1 && ws.id <= root.visibleWorkspaces
                    && map[ws.id] === undefined)
                map[ws.id] = ws
        }

        return map
    }

    // Skip the travel on the first focus after a shell start, when the
    // highlight simply appears in place.
    property bool settledOnce: false
    // Cell the highlight currently targets. A focused workspace above the
    // visible ten keeps it here instead of dragging it to the first cell, so
    // returning to a visible workspace does not fly in from the left edge.
    property int lastIndex: 0
    // Glow lag behind the highlight while it travels, in pixels. Negative is
    // left of the highlight, which is where the light trails a rightward move.
    property real trail: 0
    // Cell whose numeral is tinted. -1 while the highlight travels, so the
    // destination label lights up when the highlight lands instead of glowing
    // on the far side of the bar during the move.
    property int litIndex: 0

    function toRoman(n) {
        const r = ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
        return r[n - 1] ?? String(n)
    }

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    Behavior on trail {
        NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
    }

    onFocusedIndexChanged: {
        if (focusedIndex < 0)
            return

        const targetCenter = focusedIndex * root.cellWidth + root.cellWidth / 2

        if (!settledOnce) {
            settledOnce = true
            lastIndex = focusedIndex
            litIndex = focusedIndex
            thumb.centerX = targetCenter
            return
        }

        if (focusedIndex === lastIndex)
            return

        const distance = Math.abs(focusedIndex - lastIndex)
        const direction = focusedIndex > lastIndex ? 1 : -1
        const duration = Math.min(340, Motion.workspace + (distance - 1) * 20)

        // Travel: distance-aware so a neighbouring workspace stays snappy and a
        // far jump gets enough time to read as motion instead of a teleport.
        travel.stop()
        travel.duration = duration
        travel.to = targetCenter
        travel.start()

        // Squash and stretch along the motion: the highlight grows wider and
        // flatter while it moves, then settles back to the cell shape.
        stretchW.to = root.pillWidth + Math.min(7, 3 + distance * 0.6)
        stretchH.to = root.pillHeight - Math.min(3, 1 + distance * 0.35)
        stretchW.duration = Math.round(duration * 0.4)
        stretchH.duration = stretchW.duration
        settleW.duration = duration - stretchW.duration
        settleH.duration = settleW.duration
        travelFx.restart()

        root.trail = -direction * 5
        root.litIndex = -1
        lastIndex = focusedIndex
    }

    // If the shell starts with a workspace already focused, place the highlight
    // there without travel; a later arrival (focus read after startup) is
    // treated as an appearance as well.
    Component.onCompleted: {
        if (focusedIndex >= 0) {
            settledOnce = true
            lastIndex = focusedIndex
            litIndex = focusedIndex
            thumb.centerX = lastIndex * root.cellWidth + root.cellWidth / 2
        }
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

            // Animated travel coordinate; x follows so the pill stretches
            // around its centre instead of one edge.
            property real centerX: root.cellWidth / 2

            x: centerX - width / 2
            y: (cells.height - height) / 2
            width: root.pillWidth
            height: root.pillHeight
            visible: root.focusedIndex >= 0

            // Neon glow layer 1 (outermost, most diffuse)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.trail
                anchors.verticalCenter: parent.verticalCenter
                width: thumb.width + 10
                height: thumb.height + 3
                radius: height / 2
                color: Colors.withAlpha(Colors.primary, 0.07)
            }

            // Neon glow layer 2
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.trail
                anchors.verticalCenter: parent.verticalCenter
                width: thumb.width + 4
                height: thumb.height + 1
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

                    // Explicit model index for the bound delegate component.
                    required property int index

                    readonly property int wsId: index + 1
                    readonly property var ws: root.workspaceById[wsId]
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
                        color: root.litIndex === wsItem.wsId - 1 ? Colors.primary : Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
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
                        color: root.litIndex === wsItem.wsId - 1 ? Colors.primary : Colors.withAlpha(Colors.outline, 0.6)
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

    // Travel is declared after the cells so `thumb` already exists when the
    // animation resolves its target.
    NumberAnimation {
        id: travel
        target: thumb
        property: "centerX"
        easing.type: Easing.OutCubic
        onFinished: {
            root.trail = 0
            root.litIndex = root.lastIndex
        }
    }

    SequentialAnimation {
        id: travelFx

        ParallelAnimation {
            NumberAnimation { id: stretchW; target: thumb; property: "width"; easing.type: Easing.OutQuad }
            NumberAnimation { id: stretchH; target: thumb; property: "height"; easing.type: Easing.OutQuad }
        }

        ParallelAnimation {
            NumberAnimation { id: settleW; target: thumb; property: "width"; to: root.pillWidth; easing.type: Easing.OutCubic }
            NumberAnimation { id: settleH; target: thumb; property: "height"; to: root.pillHeight; easing.type: Easing.OutCubic }
        }
    }
}
