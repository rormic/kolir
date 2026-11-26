pragma Singleton
import QtQuick

// Shared UI animation durations, in milliseconds. Each role is pinned to the
// value used by the component it describes; roles may share a value, but a
// value is never rounded or normalized to match another role.
QtObject {
    // Theme color changes (Surface, Pill text, Toggle track).
    readonly property int color: 140
    // Crossfade of the generated palette when Matugen rewrites colors.json
    // (theme toggle, new wallpaper, Appearance change). Long enough to read as
    // one transition, short enough to stay out of the way of the bar controls,
    // which use `color`. Colors.qml applies it to every palette entry.
    readonly property int theme: 360
    // Easing of the palette crossfade. Matches the OutCubic curve the rest of
    // the shell uses for color changes.
    readonly property int themeEasing: Easing.OutCubic
    // Pointer hover accents (Pill border and icon).
    readonly property int hover: 150
    // Press feedback (IconButton scale and colors).
    readonly property int press: 130
    // Hover scale of pills.
    readonly property int scale: 140
    // Short opacity/color fades (VolumeSlider active track).
    readonly property int fade: 120
    // Position/size transitions (ProgressIndicator segments).
    readonly property int move: 180
    // Workspace switch: the bar capsule's leading edge crosses the gap first
    // and the trailing edge closes it, so this is the whole comet travel while
    // the compositor slide runs in the same range (~240-280 ms).
    readonly property int workspace: 240
    // Now-playing position line, which advances once per second.
    readonly property int mediaProgress: 800
    // Rotation transitions (settings gear).
    readonly property int rotate: 320
    // One full cycle of an endless spinner/wave animation.
    readonly property int spin: 1000
    // Popup reveal and dismissal.
    readonly property int popupEnter: 180
    readonly property int popupExit: 120
    // List item reveal and removal.
    readonly property int listEnter: 180
    readonly property int listExit: 140
    // OSD reveal and hide.
    readonly property int osd: 160
    // Embedded settings sheet reveal and dismissal (Material 3 emphasized).
    readonly property int sheetEnter: 300
    readonly property int sheetExit: 200
    // Settings page navigation (shared axis), forward and back.
    readonly property int pageForward: 260
    readonly property int pageBack: 220
}
