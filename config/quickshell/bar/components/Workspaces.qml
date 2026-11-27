pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../theme"

// Workspace switcher: occupied cells share a rail and one neon capsule travels
// between them, so a switch reads as movement instead of ten independent fades.
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
    // Occupied cells share one continuous rail: each cell paints its own slice
    // and squares off the corners that meet an occupied neighbour, so adjacent
    // workspaces read as a single capsule instead of touching pills with a
    // pinch at every boundary.
    readonly property int railHeight: 16
    readonly property int railRadius: railHeight / 2
    // Opaque on purpose: the per-cell slices and their corner caps overlap at
    // a junction, so a translucent tint would paint a lighter seam there.
    readonly property color railColor: Colors.surfaceContainerHighest

    // The highlight is exactly as tall as the rail and inset two pixels from
    // the cell edges, so it rides on the rail instead of spilling past it.
    // The outline ring then sits one pixel outside the fill, which is also the
    // smallest size that clears the focused app icon.
    readonly property int pillWidth: cellWidth - 4
    readonly property int pillHeight: railHeight
    readonly property int pillInset: (cellWidth - pillWidth) / 2

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

    function hasWindows(ws) {
        return ws ? (ws.toplevels ? ws.toplevels.values.length > 0 : false) : false
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
                NumberAnimation {
                    duration: Motion.fade
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Colors.surfaceContainerLow

                Behavior on color {
                    ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing; easing.bezierCurve: Motion.themeCurve }
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
        NumberAnimation {
            duration: Motion.durationShort2
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.standardDecelerateCurve
        }
    }

    onFocusedIndexChanged: {
        if (focusedIndex < 0)
            return

        const targetLeft = focusedIndex * root.cellWidth + root.pillInset
        const targetRight = targetLeft + root.pillWidth

        if (!settledOnce) {
            settledOnce = true
            lastIndex = focusedIndex
            thumb.leftEdge = targetLeft
            thumb.rightEdge = targetRight
            return
        }

        if (focusedIndex === lastIndex)
            return

        const distance = Math.abs(focusedIndex - lastIndex)
        const movingRight = focusedIndex > lastIndex
        const duration = Math.min(400, Motion.workspace + (distance - 1) * 24)
        const leadDuration = Math.max(90, Math.round(duration * 0.55))
        const trailDelay = Math.round(duration * 0.12)

        // The edge that leads the switch crosses the gap first; the trailing
        // edge follows after a short hold and a gentler curve. The capsule
        // stretches between them and then closes onto the destination cell, so
        // a jump reads as one travelling light instead of a sliding chip.
        leadAnim.stop()
        trailAnim.stop()

        leadAnim.property = movingRight ? "rightEdge" : "leftEdge"
        leadAnim.to = movingRight ? targetRight : targetLeft
        leadAnim.duration = leadDuration

        trailMove.property = movingRight ? "leftEdge" : "rightEdge"
        trailMove.to = movingRight ? targetLeft : targetRight
        trailMove.duration = Math.max(80, duration - trailDelay)
        trailPause.duration = trailDelay

        leadAnim.start()
        trailAnim.start()

        root.trail = movingRight ? -5 : 5
        lastIndex = focusedIndex
    }

    // If the shell starts with a workspace already focused, place the highlight
    // there without travel; a later arrival (focus read after startup) is
    // treated as an appearance as well.
    Component.onCompleted: {
        if (focusedIndex >= 0) {
            settledOnce = true
            lastIndex = focusedIndex
            thumb.leftEdge = lastIndex * root.cellWidth + root.pillInset
            thumb.rightEdge = thumb.leftEdge + root.pillWidth
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

            // The capsule is defined by its two edges rather than a centre and
            // a fixed width: the leading edge runs ahead of the trailing one,
            // so a switch stretches the pill across the gap and then closes it
            // onto the destination cell.
            property real leftEdge: root.pillInset
            property real rightEdge: root.pillInset + root.pillWidth

            readonly property real stretch: Math.max(0, width - root.pillWidth)
            // A comet that spans several cells thins its halo, so a long jump
            // does not paint a solid beam over the whole row.
            readonly property real glowFade: 1 - Math.min(0.45, stretch * 0.0025)

            x: leftEdge
            y: (cells.height - height) / 2
            width: rightEdge - leftEdge
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
                opacity: thumb.glowFade
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
                opacity: thumb.glowFade
            }

            // Main indicator
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.withAlpha(Colors.primaryContainer, 0.85)
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
                    readonly property bool hasWindow: root.hasWindows(ws)
                    readonly property bool leftOccupied: root.hasWindows(root.workspaceById[wsId - 1])
                    readonly property bool rightOccupied: root.hasWindows(root.workspaceById[wsId + 1])
                    readonly property bool isFocused: Hyprland.focusedWorkspace?.id === wsId
                    // True while the travelling capsule covers this cell's
                    // centre, so a numeral flips to the on-primary ink as the
                    // light passes over it instead of lighting up only at the
                    // destination.
                    readonly property bool underThumb: {
                        const center = (wsItem.index + 0.5) * root.cellWidth
                        return center >= thumb.leftEdge && center <= thumb.rightEdge
                    }

                    readonly property var topApp: {
                        if (!ws || !ws.toplevels) return null;
                        const tops = ws.toplevels.values;
                        return tops.length > 0 ? tops[0] : null;
                    }
                    readonly property string appClass: topApp
                        ? (topApp.wayland?.appId ?? topApp.lastIpcObject?.class ?? "")
                        : ""
                    readonly property bool iconShown: hasWindow && appIcon.ready
                    // Keep the last resolved class while a closing window
                    // fades its icon out, so the cell never blanks before the
                    // numeral has faded in.
                    property string lastAppClass: ""
                    onAppClassChanged: {
                        if (appClass.length > 0)
                            lastAppClass = appClass
                    }

                    implicitWidth: root.cellWidth
                    implicitHeight: root.cellHeight

                    // Occupied rail. Each cell paints its own slice; the two
                    // caps below square off the corners that touch an occupied
                    // neighbour, so a run of occupied workspaces reads as one
                    // capsule with rounded outer ends.
                    Item {
                        id: rail

                        anchors.centerIn: parent
                        width: root.cellWidth + 1
                        height: root.railHeight
                        opacity: wsItem.hasWindow ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.fade
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.railRadius
                            color: root.railColor
                        }

                        Rectangle {
                            visible: wsItem.hasWindow && (wsItem.leftOccupied || opacity > 0)
                            opacity: wsItem.leftOccupied ? 1 : 0
                            width: root.railRadius
                            height: parent.height
                            color: root.railColor

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.fade
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Motion.standardDecelerateCurve
                                }
                            }
                        }

                        Rectangle {
                            visible: wsItem.hasWindow && (wsItem.rightOccupied || opacity > 0)
                            opacity: wsItem.rightOccupied ? 1 : 0
                            anchors.right: parent.right
                            width: root.railRadius
                            height: parent.height
                            color: root.railColor

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.fade
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Motion.standardDecelerateCurve
                                }
                            }
                        }
                    }

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
                        appClass: wsItem.hasWindow ? wsItem.appClass : wsItem.lastAppClass
                        // 14 px lands on whole pixels inside the 20×22 cell
                        // (3 px and 4 px insets), so circular logos such as
                        // Zen's stay crisp and concentric with the focus ring;
                        // an odd 15 px icon sat on half pixels and read as a
                        // smeared, off-centre glyph.
                        iconSize: 14
                        opacity: wsItem.iconShown ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.fade
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.toRoman(wsItem.wsId)
                        opacity: wsItem.iconShown ? 0 : 1
                        visible: opacity > 0
                        color: wsItem.underThumb
                            ? Colors.onPrimaryContainer
                            : Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                        font.family: Typography.barFont
                        font.pixelSize: wsItem.wsId === 8 ? 8 : 9
                        font.weight: Typography.weight.bold

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.fade
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing; easing.bezierCurve: Motion.themeCurve }
                        }
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

        // The active outline is drawn above the row, so an app icon can never
        // hide the selection. It follows the same animated edges as the fill,
        // which keeps the lead/trail effect on the whole comet.
        Rectangle {
            id: focusRing

            x: thumb.leftEdge - 1
            y: thumb.y - 1
            width: thumb.width + 2
            height: thumb.height + 2
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: Colors.primary
            visible: thumb.visible
        }
    }

    // Motion is declared after the cells so `thumb` already exists. The leading
    // edge runs first; the trailing edge holds the capsule stretched for a beat
    // and then closes it onto the destination. A new switch stops both and
    // retargets from the current values, so quick workspace hopping never jumps
    // back to a stale edge.
    NumberAnimation {
        id: leadAnim
        target: thumb
        property: "rightEdge"
        // Leading edge: content entering, so emphasized decelerate.
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.emphasizedDecelerateCurve
    }

    SequentialAnimation {
        id: trailAnim

        // `SequentialAnimation` is the animation that actually completes last;
        // a child NumberAnimation inside it does not deliver its own
        // `onFinished` here, so the trail is cleared on the sequence.
        onFinished: root.trail = 0

        PauseAnimation { id: trailPause }

        NumberAnimation {
            id: trailMove
            target: thumb
            property: "leftEdge"
            // Trailing edge closes on the emphasized (both ends) curve.
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedCurve
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
}
