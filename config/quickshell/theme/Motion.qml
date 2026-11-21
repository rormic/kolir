pragma Singleton
import QtQuick

// Shared UI animation durations, in milliseconds. Each role is pinned to the
// value used by the component it describes; roles may share a value, but a
// value is never rounded or normalized to match another role.
QtObject {
    // Theme color changes (Surface, Pill text, Toggle track).
    readonly property int color: 140
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
    readonly property int osd: 180
}
