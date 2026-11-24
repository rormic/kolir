pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
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

    // Special workspace (the SUPER+S scratchpad) is not represented by
    // `focusedWorkspace`: Hyprland keeps the normal workspace focused and
    // reports the scratchpad in a separate monitor field. Quickshell only
    // refreshes `lastIpcObject` on demand, so the startup snapshot seeds the
    // state and the `activespecial` event keeps it current afterwards. No
    // polling: the event socket is already open for the rest of the bar.
    readonly property bool initialSpecialOpen: {
        const monitors = Hyprland.monitors.values
        for (let i = 0; i < monitors.length; i++) {
            const special = monitors[i].lastIpcObject?.specialWorkspace
            if (special && (special.name ?? "").length > 0)
                return true
        }
        return false
    }
    property bool specialEventSeen: false
    property bool specialEventOpen: false
    readonly property bool specialOpen: specialEventSeen ? specialEventOpen : initialSpecialOpen
    // Rainbow drift timing: 20 fps over one full rainbow width in 5.2 s. A
    // smooth, slow gradient does not need 30/60 Hz, and fewer commits keep the
    // compositor and GPU almost idle while the scratchpad is open.
    readonly property int specialWashFrame: 50
    readonly property int specialWashCycle: 5200

    function toRoman(n) {
        const r = ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
        return r[n - 1] ?? String(n)
    }

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + Dimensions.padding.chipHorizontal
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // Rainbow wash for the scratchpad. The animated fill is drawn in its own
    // small Top-layer surface instead of inside the bar: a frame in the bar
    // repainted the whole 2560x1440 shell layer, while this window only covers
    // the pill. The window is click-through, has no exclusive zone and covers
    // the pill's icons/numerals with the opaque wash; the bar underneath keeps
    // handling clicks. The Shape clips the gradient to the capsule itself.
    PanelWindow {
        id: specialWashWindow

        // The wash follows the pill when the bar reflows. mapFromItem() is an
        // imperative call and does not register item positions as binding
        // dependencies, so summing the parent chain keeps the binding live.
        readonly property point origin: {
            let x = 0
            let y = 0
            let item = root
            while (item) {
                x += item.x
                y += item.y
                item = item.parent
            }
            return Qt.point(x, y)
        }

        anchors {
            top: true
            left: true
        }
        margins {
            // A Top-layer surface is laid out below the bar's 30 px exclusive
            // zone, so subtract it to land on the strip rather than under it.
            top: Math.round(origin.y) - Dimensions.bar.height
            left: Math.round(origin.x)
        }

        implicitWidth: root.width
        implicitHeight: root.height
        color: "transparent"
        // Stay mapped through the fade-out, then unmap the surface.
        visible: root.specialOpen || washContent.opacity > 0

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "workspace-wash"
        WlrLayershell.exclusiveZone: 0
        mask: Region {}

        // The window is fully opaque: the bar-strip colour fills the corners
        // outside the capsule, so the compositor does not have to blend this
        // surface over the bar every frame. The Surface and the 1 px ring
        // around the Shape reproduce the pill that the bar paints underneath.
        // The whole pill fades as one, revealing the normal pill underneath
        // instead of flashing an icon-less surface while the wash disappears.
        Item {
            id: washContent

            anchors.fill: parent
            opacity: root.specialOpen ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Motion.fade; easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.fill: parent
                color: Colors.surfaceContainerLow

                Behavior on color {
                    ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
                }
            }

            Surface {
                anchors.fill: parent
                radius: root.radius
                surfaceColor: root.surfaceColor
                borderColor: root.borderColor
                borderWidth: root.borderWidth
            }

            Shape {
                id: specialWash

                anchors.fill: parent
                anchors.margins: root.borderWidth
                preferredRendererType: Shape.CurveRenderer

                // Fraction of the rainbow the gradient has travelled. One full
                // cycle is one pill width, so the wrap lands on identical colors.
                property real phase: 0

                ShapePath {
                    strokeWidth: 0

                    fillGradient: LinearGradient {
                        x1: -specialWash.width * specialWash.phase
                        y1: specialWash.height / 2
                        x2: specialWash.width - specialWash.width * specialWash.phase
                        y2: specialWash.height / 2
                        spread: ShapeGradient.RepeatSpread

                        GradientStop { position: 0.000; color: "#ff2d55" }
                        GradientStop { position: 0.143; color: "#ff7a1a" }
                        GradientStop { position: 0.286; color: "#ffd60a" }
                        GradientStop { position: 0.429; color: "#30d158" }
                        GradientStop { position: 0.571; color: "#2ed3c6" }
                        GradientStop { position: 0.714; color: "#2d9bff" }
                        GradientStop { position: 0.857; color: "#b45cff" }
                        GradientStop { position: 1.000; color: "#ff2d55" }
                    }

                    PathRectangle {
                        width: specialWash.width
                        height: specialWash.height
                        radius: root.radius
                    }
                }
            }
        }
    }

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

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "activespecial")
                return

            // "activespecial" carries the special workspace name and its
            // monitor; an empty name is the close event.
            const data = event.parse(2)
            root.specialEventSeen = true
            root.specialEventOpen = (data[0] ?? "").length > 0
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

    // One rainbow width per loop. A 20 Hz timer drives the slow drift instead
    // of a 60 Hz animation, keeping the redraw cost low while the scratchpad is
    // open; the timer stops with the fill, so an idle bar schedules nothing.
    Timer {
        id: specialWashTicker

        interval: root.specialWashFrame
        repeat: true
        running: root.specialOpen
        onTriggered: {
            specialWash.phase = (specialWash.phase + interval / root.specialWashCycle) % 1
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
