pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property QtObject radius: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
        readonly property int full: 9999
    }

    readonly property QtObject bar: QtObject {
        readonly property int height: 30
        // Floating gap above the bar (also used as the notification offset).
        readonly property int margin: 8
        // Side inset of the bar surface (matches Hyprland's gaps_out), so the
        // bar edges line up with the window columns.
        readonly property int sideMargin: 8
        // The surface floats away from every screen edge.
        readonly property int radius: 12
        readonly property int contentHeight: 24
    }

    readonly property QtObject control: QtObject {
        readonly property int height: 24
        readonly property int iconButton: 24
        readonly property int touchTarget: 30
    }

    readonly property QtObject icon: QtObject {
        readonly property int small: 13
        readonly property int medium: 15
        readonly property int large: 17
        readonly property int extraLarge: 20
    }

    readonly property QtObject padding: QtObject {
        readonly property int horizontal: 10
        readonly property int vertical: 4
        readonly property int chipHorizontal: 8
        readonly property int barContent: 12
    }

    readonly property QtObject spacing: QtObject {
        readonly property int none: 0
        readonly property int extraSmall: 2
        readonly property int small: 4
        readonly property int medium: 8
        readonly property int large: 16
    }

    readonly property QtObject insideBarSize: QtObject {
        readonly property int rectangleHight: root.bar.contentHeight
    }
}
