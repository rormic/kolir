import "../theme"
import "../settings"
import "./components"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// Caelestia-style docked bar with a screen frame.
//
// The window covers the whole screen and paints the bar surface as a ring: the
// top strip is the bar, the sides and bottom fill the window gaps, and the
// desktop is a rounded cut-out. Because the surface is at the top layer, the
// rounded cut-out also frames the corners of the first window row instead of
// letting the wallpaper show between the bar, the screen edges and the windows.
// `Dimensions.frame.thickness` must match Hyprland's gaps_out.
PanelWindow {
    id: bar
    WlrLayershell.namespace: "bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: Dimensions.bar.height
    // The settings popout lives in this surface instead of a separate window.
    // OnDemand lets the menu receive keyboard focus (Escape, Wi-Fi password)
    // after it is clicked without stealing focus when it is closed.
    WlrLayershell.keyboardFocus: settingsMenu.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
    }

    // wlr-layer-shell ignores the exclusive zone of a surface anchored to both
    // ends of an axis, so the window is anchored to the top only and sized to
    // the whole screen instead of anchoring bottom too.
    implicitHeight: bar.screen ? bar.screen.height : 0

    color: "transparent"

    readonly property int frameThickness: Dimensions.frame.thickness
    readonly property int holeRadius: Dimensions.frame.radius
    // The cut-out starts below the bar plus one frame thickness, exactly where
    // the first window row starts.
    readonly property int holeY: Dimensions.bar.height + Dimensions.frame.thickness

    // Bar input region: the window minus the rounded desktop cut-out. This is
    // kept as a fixed Region (like the frame drawing) so the compositor sees a
    // stable input region while the bar is closed.
    readonly property Region frameMask: Region {
        x: 0
        y: 0
        width: bar.width
        height: bar.height

        Region {
            x: bar.frameThickness
            y: bar.holeY
            width: bar.width - bar.frameThickness * 2
            height: bar.height - bar.holeY - bar.frameThickness
            radius: bar.holeRadius
            intersection: Intersection.Subtract
        }
    }

    // While the settings popout is open the whole surface becomes modal, so
    // the full-window dismissal layer can receive outside clicks.
    readonly property Region modalMask: Region {
        x: 0
        y: 0
        width: bar.width
        height: bar.height
    }

    mask: settingsMenu.modal ? modalMask : frameMask

    // Outer rectangle (the whole surface) minus the rounded desktop cut-out.
    readonly property string framePath: {
        const w = bar.width;
        const h = bar.height;
        const t = bar.frameThickness;
        const r = bar.holeRadius;
        const y0 = bar.holeY;
        const hx = t;
        const hw = w - t * 2;
        const hh = h - y0 - t;
        const hole = `M${hx + r} ${y0} H${hx + hw - r} A${r} ${r} 0 0 1 ${hx + hw} ${y0 + r}` + ` V${y0 + hh - r} A${r} ${r} 0 0 1 ${hx + hw - r} ${y0 + hh}` + ` H${hx + r} A${r} ${r} 0 0 1 ${hx} ${y0 + hh - r}` + ` V${y0 + r} A${r} ${r} 0 0 1 ${hx + r} ${y0} Z`;
        return `M0 0 H${w} V${h} H0 Z ${hole}`;
    }

    // The frame is interactive (bar content lives on it); the desktop cut-out
    // is click-through. The popout lives in the same surface and switches the
    // window to the full-screen modal mask above.
    //
    // Keep the default geometry renderer here: CurveRenderer flattens the
    // rounded cut-out about 1px inside the path, so the frame covers the outer
    // row of the window border where the two edges meet at the corners. The
    // default renderer keeps the cut-out on the decorated window box, leaving
    // the border intact.
    Shape {
        anchors.fill: parent

        ShapePath {
            fillColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.94)
            strokeWidth: 0
            fillRule: ShapePath.OddEvenFill

            PathSvg {
                path: bar.framePath
            }
        }
    }

    // Subtle top highlight
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.18)
    }

    Item {
        id: content

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Dimensions.bar.height
        z: 2

        // Settings trigger. The panel is drawn by the full-window overlay
        // below, but the button stays in the bar strip above it.
        IconButton {
            id: settingsTrigger

            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent
            anchors.verticalCenter: parent.verticalCenter
            icon: Icons.settings
            iconSize: Dimensions.icon.large
            iconOffsetX: -0.5
            iconOffsetY: 1
            active: settingsMenu.opened
            rotation: settingsMenu.opened ? 90 : 0
            onClicked: settingsMenu.toggle()

            Behavior on rotation {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
        }

        // Left: active window, after the settings button slot.
        ActiveWindow {
            id: activeWindow
            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent + Dimensions.control.iconButton + Dimensions.spacing.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(190, Math.max(120, content.width * 0.16))
        }

        // Center: workspaces
        Workspaces {
            id: workspaces
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: workspaces.cellWidth / 2
        }

        // Left of center: now playing
        NowPlaying {
            id: nowPlaying
            enabled: content.width >= 1100
            anchors.right: workspaces.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        // Right of center: clock
        Clock {
            id: clock
            anchors.left: workspaces.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        // Right edge
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Dimensions.padding.barContent
            anchors.verticalCenter: parent.verticalCenter
            spacing: Dimensions.spacing.small

            Tray            { anchors.verticalCenter: parent.verticalCenter }
            RecordingStatus { anchors.verticalCenter: parent.verticalCenter }
            Brightness      { anchors.verticalCenter: parent.verticalCenter }
            Volume          { anchors.verticalCenter: parent.verticalCenter }
            ThemeToggle     { anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // Settings panel overlay. It fills the bar window, sits above the frame but
    // below the bar content, and paints the popout below the bar as a single
    // connected surface.
    SettingsMenu {
        id: settingsMenu
        anchors.fill: parent
        z: 1
    }
}
