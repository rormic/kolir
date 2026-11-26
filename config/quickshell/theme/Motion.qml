pragma Singleton
import QtQuick

// Shared UI animation tokens. Durations, curves and springs come from
// Material 3 Expressive; the semantic roles at the bottom map components onto
// those tokens. Roles may intentionally share a token now.
QtObject {
    // Material 3 duration tokens, in milliseconds
    // (https://m3.material.io/styles/motion/easing-and-duration/tokens-specs).
    readonly property int durationShort1: 50
    readonly property int durationShort2: 100
    readonly property int durationShort3: 150
    readonly property int durationShort4: 200
    readonly property int durationMedium1: 250
    readonly property int durationMedium2: 300
    readonly property int durationMedium3: 350
    readonly property int durationMedium4: 400
    readonly property int durationLong1: 450
    readonly property int durationLong2: 500
    readonly property int durationLong3: 550
    readonly property int durationLong4: 600
    readonly property int durationExtraLong1: 700
    readonly property int durationExtraLong2: 800
    readonly property int durationExtraLong3: 900
    readonly property int durationExtraLong4: 1000

    // Material 3 easing curves
    // (https://m3.material.io/styles/motion/easing-and-duration/tokens-specs).
    // Entering content uses emphasized decelerate, leaving content uses
    // emphasized accelerate; standard decelerate covers hover/press/fades.
    readonly property var emphasizedCurve: [0.2, 0, 0, 1]
    readonly property var emphasizedDecelerateCurve: [0.05, 0.7, 0.1, 1]
    readonly property var emphasizedAccelerateCurve: [0.3, 0, 0.8, 0.15]
    readonly property var standardCurve: [0.2, 0, 0, 1]
    readonly property var standardDecelerateCurve: [0, 0, 0, 1]
    readonly property var standardAccelerateCurve: [0.3, 0, 1, 1]
    readonly property var linearCurve: [0, 0, 1, 1]
    // Palette/surface colour crossfade. The generated palette fades through
    // the M3 emphasized curve rather than a spatial spring.
    readonly property int themeEasing: Easing.Bezier
    readonly property var themeCurve: [0.2, 0, 0, 1]

    // Material 3 Expressive motion physics, spatial springs
    // (https://m3.material.io/styles/motion/overview/specs). Stiffness and
    // damping ratio are the M3 values; Qt's SpringAnimation integrates at a
    // fixed 16 ms step, so its `spring` is stiffness * 0.016 and its
    // `damping` is 2 * dampingRatio * sqrt(stiffness) * 0.016.
    //   default: 380 / 0.8  -> 6.08 / 0.499
    //   fast:    800 / 0.6  -> 12.8 / 0.543
    //   slow:    200 / 0.8  -> 3.2  / 0.362
    readonly property real spatialSpring: 6.08
    readonly property real spatialSpringDamping: 0.499
    readonly property real spatialSpringFast: 12.8
    readonly property real spatialSpringFastDamping: 0.543
    readonly property real spatialSpringSlow: 3.2
    readonly property real spatialSpringSlowDamping: 0.362
    // Qt's own epsilon guidance: 0.25 for positions, 0.005 for scale.
    readonly property real springPositionEpsilon: 0.25
    readonly property real springScaleEpsilon: 0.005

    // Semantic duration roles.
    readonly property int color: durationShort3
    readonly property int theme: durationMedium4
    readonly property int hover: durationShort3
    readonly property int press: durationShort2
    readonly property int scale: durationShort3
    readonly property int fade: durationShort2
    readonly property int move: durationShort4
    // The workspace capsule is one tuned travel (leading edge first, trailing
    // edge closes later), so it keeps its own duration instead of a token.
    readonly property int workspace: 240
    // Now-playing position line, which advances once per second.
    readonly property int mediaProgress: 800
    readonly property int rotate: durationMedium2
    // One full cycle of an endless spinner/wave animation.
    readonly property int spin: 1000
    // Popup reveal and dismissal.
    readonly property int popupEnter: durationMedium1
    readonly property int popupExit: durationShort3
    // List item reveal and removal.
    readonly property int listEnter: durationShort4
    readonly property int listExit: durationShort3
    // OSD reveal and hide.
    readonly property int osd: durationShort3
    // Embedded settings sheet reveal and dismissal (Material 3 emphasized).
    readonly property int sheetEnter: durationMedium2
    readonly property int sheetExit: durationShort4
    // Settings page navigation (shared axis), forward and back.
    readonly property int pageForward: durationMedium2
    readonly property int pageBack: durationMedium1
}
