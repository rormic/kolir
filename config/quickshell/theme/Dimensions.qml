pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property QtObject radius: QtObject {
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraExtraLarge: 48
        readonly property int full: 9999
    }

    readonly property QtObject bar: QtObject {
        readonly property int height: 30
        // No offset from the screen edges: the bar is docked flush. Kept as a
        // token because popups offset themselves from it.
        readonly property int margin: 0
        // Minimum width of the two chips flanking the workspaces pill (the
        // clock and the now-playing island). The island mirrors the clock's
        // implicit width, so the pill stays visually centered while no media
        // is playing instead of losing its left neighbour.
        readonly property int centerSlot: 184
    }

    // Screen frame drawn around the desktop, caelestia style: the bar surface
    // fills the window gaps so the desktop is a single rounded cut-out.
    // `thickness` must match Hyprland's gaps_out or the frame will either
    // leave a seam or slide under the windows.
    readonly property QtObject frame: QtObject {
        readonly property int thickness: 4
        // Must equal decoration.rounding + border_size: that is the curve the
        // window border actually renders. A smaller radius leaves a dark gap
        // at the corners; a larger one makes the two arcs cross and clips the
        // border into crooked slivers.
        readonly property int radius: 30
    }

    readonly property QtObject control: QtObject {
        readonly property int height: 24
        readonly property int iconButton: 24
    }

    readonly property QtObject icon: QtObject {
        readonly property int small: 13
        readonly property int medium: 15
        readonly property int large: 17
        readonly property int extraLarge: 20
    }

    // Now-playing island: rounded cover art, text viewport and the thin
    // progress line on the pill's bottom edge.
    readonly property QtObject media: QtObject {
        readonly property int cover: 18
        readonly property int coverRadius: 5
        readonly property int coverSpacing: 6
        // Text viewport at rest (play/pause only) and while hovered, when the
        // prev/next buttons take part of the island.
        readonly property int textMaxWidth: 150
        readonly property int textCondensedWidth: 96
        // Thin progress line on the pill's bottom edge.
        readonly property int progressThickness: 2
        readonly property int progressInset: 6
        readonly property int progressBottomMargin: 2
        readonly property int transportSpacing: 2
    }

    readonly property QtObject padding: QtObject {
        readonly property int chipHorizontal: 8
        readonly property int barContent: 12
    }

    // Material 3 linear progress indicator metrics.
    readonly property QtObject progress: QtObject {
        readonly property int thickness: 4
        readonly property int gap: 4
        readonly property int stopIndicator: 4
        readonly property int waveAmplitude: 3
        readonly property int wavelength: 40
    }

    readonly property QtObject spacing: QtObject {
        readonly property int small: 4
    }
}
