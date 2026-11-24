pragma ComponentBehavior: Bound

import "../services"
import "../theme"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Caelestia-style screen frame, split out of the bar so it can sit below the
// windows. The surface covers the whole screen and paints the window gaps as
// a ring around the rounded desktop, so the wallpaper does not show between
// the screen edges and the first window row.
//
// FrameService selects between two variants:
//   - "ring": the classic full frame in the bar colour, with the desktop in a
//     rounded cut-out inset by `gaps_out`;
//   - "corners": corner spandrels only. The upper two share the bar colour,
//     the lower two are black, the side/bottom strips disappear, and the
//     window sides run flush to the screen edge (gaps_out = 0).
//
// The Bottom layer is what removes the border clipping: windows are
// composited above the frame, so their borders can never be covered or cut
// by the rounded cut-out. `Dimensions.frame.thickness` must match Hyprland's
// gap in the ring style and `Dimensions.frame.radius` its rounding + border
// size in both styles.
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

    // Corner-only variant: no strips and no outer gaps, so the spandrels sit
    // flush in the physical screen corners. The upper two keep the bar colour
    // (the bar flows straight into them, as in the ring style); the lower two
    // are black.
    readonly property bool cornerStyle: FrameService.corners
    readonly property int cornerInset: frame.cornerStyle ? 0 : frame.thickness
    readonly property int cornerTopY: frame.cornerStyle
        ? frame.barHeight
        : frame.holeY
    readonly property int cornerBottomY: frame.cornerStyle
        ? frame.height - frame.radius
        : frame.height - frame.thickness - frame.radius

    // Opaque on purpose: the frame ring is part of the same chrome as the bar
    // and the settings sheet, so it must not tint with the wallpaper. A
    // translucent ring reads as a see-through outline in the dark theme,
    // where 6% of a bright wallpaper is very visible. The lower corners of
    // the corner-only style are black by design, in both themes.
    readonly property color ringColor: Colors.surfaceContainerLow
    readonly property color bottomCornerColor: frame.cornerStyle
        ? Colors.frameCorner
        : Colors.surfaceContainerLow

    // Keep Hyprland's outer gap in sync with the selected style: the ring
    // needs room for its strips, the corner-only frame fills the screen edge.
    // `hyprctl eval` is the runtime form of `hl.config` used by the Lua
    // config. hyprland.lua reads the same frame.json at startup, so a fresh
    // session and a plain `hyprctl reload` already start in the saved style.
    property bool gapsQueued: false

    function applyGaps() {
        if (gapsProcess.running) {
            frame.gapsQueued = true;
            return;
        }

        frame.gapsQueued = false;
        gapsProcess.command = [
            "hyprctl", "eval",
            "hl.config({ general = { gaps_out = "
                + (frame.cornerStyle ? 0 : frame.thickness) + " } })",
        ];
        gapsProcess.running = true;
    }

    // The saved style is already applied by hyprland.lua before the shell
    // starts; only a live toggle needs to push new gaps to Hyprland.
    Connections {
        target: FrameService

        function onStyleChanged() {
            frame.applyGaps();
        }
    }

    property Process gapsProcess: Process {
        command: ["hyprctl", "eval", "hl.config({})"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    console.warn("Frame: gaps update failed:", output);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("Frame: hyprctl eval exited with", exitCode);

            if (frame.gapsQueued)
                frame.applyGaps();
        }
    }

    // The ring is an outer rectangle minus a rounded cut-out, but only its
    // four corners are curved. Drawing the whole thing as one shape forced a
    // multisampled layer the size of the screen (2560x1440 x 4 samples, ~59
    // MB of render buffer) so that four 30x30 arcs would be antialiased.
    //
    // So the straight parts are plain axis-aligned rectangles, which are crisp
    // at integer geometry without any antialiasing, and each corner is its own
    // 30x30 spandrel: the square corner minus the quarter circle. Those are
    // drawn on a Canvas, which antialiases the arc itself and lets us repaint
    // explicitly.
    //
    // A Shape was the natural fit here, but its ShapePath only repaints when
    // the geometry changes: a fill-colour-only change never reached the
    // screen, so the corners kept the Colors.qml placeholder after the first
    // palette load until the next palette animation happened to redraw them.
    //
    // `cornerPath()` draws one spandrel in a 30x30 box: from the ring corner
    // along one box edge to the arc's tangency point, around the arc to the
    // other tangency point, and back. The arc is the same quarter circle the
    // single cut-out path used, so the inner edge stays exactly where it was.
    function cornerPath(ctx, corner, r) {
        // Arc centre, ring corner and the tangency point the arc starts from,
        // all in the 30x30 box of this corner.
        const centres = [[r, r], [0, r], [r, 0], [0, 0]];
        const ringCorners = [[0, 0], [r, 0], [0, r], [r, r]];
        const from = [[r, 0], [0, 0], [0, 0], [r, 0]];
        // Canvas angles grow clockwise on screen, so a quarter that turns the
        // other way has to ask for an anticlockwise sweep.
        const startAngles = [-Math.PI / 2, -Math.PI / 2, Math.PI, 0];
        const endAngles = [Math.PI, 0, Math.PI / 2, Math.PI / 2];
        const anticlockwise = [true, false, true, false];

        ctx.moveTo(ringCorners[corner][0], ringCorners[corner][1]);
        ctx.lineTo(from[corner][0], from[corner][1]);
        ctx.arc(centres[corner][0], centres[corner][1], r,
                startAngles[corner], endAngles[corner], anticlockwise[corner]);
        ctx.closePath();
    }

    // One rounded corner of the cut-out. Repainted only when the palette or
    // the geometry changes, never per frame.
    component CornerRing: Canvas {
        id: cornerRing

        property int corner: 0
        property color fillColor: "transparent"

        width: frame.radius
        height: frame.radius

        onFillColorChanged: cornerRing.requestPaint()
        onCornerChanged: cornerRing.requestPaint()
        onWidthChanged: cornerRing.requestPaint()
        onHeightChanged: cornerRing.requestPaint()

        onPaint: {
            const ctx = cornerRing.getContext("2d");
            ctx.reset();
            ctx.antialias = true;
            ctx.beginPath();
            frame.cornerPath(ctx, cornerRing.corner,
                             Math.min(cornerRing.width, cornerRing.height));
            ctx.fillStyle = cornerRing.fillColor;
            ctx.fill();
        }
    }

    // Top strip, from the bar's bottom edge down to the cut-out. The classic
    // ring only: the corner style runs the windows up to the bar.
    Rectangle {
        x: 0
        y: frame.barHeight
        width: frame.width
        height: frame.thickness
        color: frame.ringColor
        visible: !frame.cornerStyle
    }

    // Bottom strip, up to the last pixel row.
    Rectangle {
        x: 0
        y: frame.height - frame.thickness
        width: frame.width
        height: frame.thickness
        color: frame.ringColor
        visible: !frame.cornerStyle
    }

    // Left and right strips run the full outer height, so the four corners of
    // the outer rectangle are already covered and the rings only have to fill
    // the cut-out corners.
    Rectangle {
        x: 0
        y: frame.barHeight
        width: frame.thickness
        height: frame.height - frame.barHeight
        color: frame.ringColor
        visible: !frame.cornerStyle
    }

    Rectangle {
        x: frame.width - frame.thickness
        y: frame.barHeight
        width: frame.thickness
        height: frame.height - frame.barHeight
        color: frame.ringColor
        visible: !frame.cornerStyle
    }

    // One ring per rounded corner of the cut-out. In the corner style these
    // are the only painted pieces: the top pair shares the bar colour, the
    // bottom pair is black.
    CornerRing {
        corner: 0
        fillColor: frame.ringColor
        x: frame.cornerInset
        y: frame.cornerTopY
    }

    CornerRing {
        corner: 1
        fillColor: frame.ringColor
        x: frame.width - frame.cornerInset - frame.radius
        y: frame.cornerTopY
    }

    CornerRing {
        corner: 2
        fillColor: frame.bottomCornerColor
        x: frame.cornerInset
        y: frame.cornerBottomY
    }

    CornerRing {
        corner: 3
        fillColor: frame.bottomCornerColor
        x: frame.width - frame.cornerInset - frame.radius
        y: frame.cornerBottomY
    }
}
