import "../theme"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// Caelestia-style screen frame, split out of the bar so it can sit below the
// windows. The surface covers the whole screen and paints the window gaps as
// a ring around the rounded desktop, so the wallpaper does not show between
// the screen edges and the first window row.
//
// The Bottom layer is what removes the border clipping: windows are
// composited above the frame, so their borders can never be covered or cut
// by the rounded cut-out. `Dimensions.frame.thickness` must match Hyprland's
// gaps_out and `Dimensions.frame.radius` its rounding + border size.
PanelWindow {
    id: frame

    WlrLayershell.namespace: "frame"
    WlrLayershell.layer: WlrLayer.Bottom
    // The bar reserves a 30px exclusive zone on the Top layer; ignoring
    // exclusive zones keeps this surface anchored to the full screen instead
    // of being shifted or shrunk by that reservation.
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    // Purely decorative: the empty mask leaves the whole surface
    // click-through, so windows and the desktop keep receiving input through
    // the frame.
    mask: Region {}

    readonly property int barHeight: Dimensions.bar.height
    readonly property int thickness: Dimensions.frame.thickness
    // The true window radius: the frame renders underneath the windows, so
    // its edge no longer has to dodge their borders.
    readonly property int radius: Dimensions.frame.radius
    // The cut-out starts below the bar plus one frame thickness, exactly
    // where the first window row starts.
    readonly property int holeY: frame.barHeight + frame.thickness

    // Ring around the desktop: an outer rectangle starting at the bar strip
    // (Bar.qml paints 0..barHeight on the Top layer, so the two surfaces
    // never overlap) minus the rounded cut-out on the decorated window box.
    readonly property string framePath: {
        const w = frame.width;
        const h = frame.height;
        const t = frame.thickness;
        const r = frame.radius;
        const y0 = frame.holeY;
        const hx = t;
        const hw = w - t * 2;
        const hh = h - y0 - t;
        const hole = `M${hx + r} ${y0} H${hx + hw - r} A${r} ${r} 0 0 1 ${hx + hw} ${y0 + r}` + ` V${y0 + hh - r} A${r} ${r} 0 0 1 ${hx + hw - r} ${y0 + hh}` + ` H${hx + r} A${r} ${r} 0 0 1 ${hx} ${y0 + hh - r}` + ` V${y0 + r} A${r} ${r} 0 0 1 ${hx + r} ${y0} Z`;
        return `M0 ${frame.barHeight} H${w} V${h} H0 Z ${hole}`;
    }

    // Keep the default geometry renderer: it rasterizes the path exactly
    // where it is defined, while CurveRenderer would pull the rounded hole
    // about 1px inside it. The default renderer has no antialiasing of its
    // own, so the Shape renders through a multisampled layer that smooths
    // the cut-out edge where it frames the empty desktop.
    Shape {
        anchors.fill: parent

        // MSAA layer: antialiases the rounded cut-out without moving it.
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            // Opaque on purpose: the frame ring is part of the same chrome as
            // the bar and the settings sheet, so it must not tint with the
            // wallpaper. A translucent ring reads as a see-through outline in
            // the dark theme, where 6% of a bright wallpaper is very visible.
            fillColor: Colors.surfaceContainerLow
            strokeWidth: 0
            fillRule: ShapePath.OddEvenFill

            PathSvg {
                path: frame.framePath
            }
        }
    }
}
