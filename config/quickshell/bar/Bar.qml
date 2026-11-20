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
    // is click-through. The rounded corners count as frame, so clicks in the
    // small corner slivers stay on the bar instead of hitting a window.
    mask: Region {
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

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

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

    // Neon bottom line — the signature accent, kept at the bottom of the bar
    // content and above the frame band so it never crosses the rounded
    // desktop cut-out.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
        }
        y: Dimensions.bar.height - 1
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.25; color: Colors.withAlpha(Colors.primary, 0.4) }
            GradientStop { position: 0.5;  color: Colors.withAlpha(Colors.primary, 0.85) }
            GradientStop { position: 0.75; color: Colors.withAlpha(Colors.primary, 0.4) }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }

    Item {
        id: content

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Dimensions.bar.height

        // Far left: settings launcher
        SettingsMenu {
            id: settingsMenu
            anchors.left: parent.left
            anchors.leftMargin: Dimensions.padding.barContent
            anchors.verticalCenter: parent.verticalCenter
        }

        // Left: active window
        ActiveWindow {
            id: activeWindow
            anchors.left: settingsMenu.right
            anchors.leftMargin: Dimensions.spacing.small
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
}
