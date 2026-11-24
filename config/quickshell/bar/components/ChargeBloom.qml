import QtQuick
import QtQuick.Shapes
import "../../theme"

// One-shot charge bloom for the battery chip.
//
// `play()` runs three effects that are independent of the chip's own pulse:
//   - a soft primary halo that expands behind the pill,
//   - a thin ring that expands just past the pill's edge, and
//   - a primary streak that runs left across the bar's bottom edge.
//
// Nothing runs while the component is idle, so an always-plugged laptop does
// not schedule frames after the initial effect. The caller owns the chip
// scale pulse because the Pill already binds `scale` to hover.
Item {
    id: root

    // Distance from the chip's left edge to the bar's left edge. The caller
    // owns this because only the bar knows where the chip sits; the default
    // keeps a standalone preview readable.
    property real sweepDistance: 240

    // Local durations: this is a one-off optical effect, not a shared motion
    // role. The halo and the streak deliberately end at different times.
    readonly property int haloDuration: 620
    readonly property int sweepDuration: 1100
    readonly property int sweepDelay: 60
    readonly property int sweepLength: 140

    // A square radial gradient scaled down vertically: its colour reaches
    // fully transparent exactly at the bar's edges, so the glow never ends in
    // a visible straight cut (or spills over the windows below the bar).
    readonly property real haloSize: Math.max(56, root.width + 16)
    readonly property real haloScaleY: Dimensions.bar.height / root.haloSize

    function play() {
        bloom.restart();
    }

    Shape {
        id: halo

        anchors.centerIn: parent
        width: root.haloSize
        height: root.haloSize
        opacity: 0
        visible: opacity > 0.001
        preferredRendererType: Shape.CurveRenderer

        transform: Scale {
            origin.x: root.haloSize / 2
            origin.y: root.haloSize / 2
            yScale: root.haloScaleY
        }

        ShapePath {
            strokeWidth: 0

            fillGradient: RadialGradient {
                centerX: root.haloSize / 2
                centerY: root.haloSize / 2
                centerRadius: root.haloSize / 2
                focalX: root.haloSize / 2
                focalY: root.haloSize / 2
                focalRadius: 0

                // The centre is hidden behind the opaque pill; the visible rim
                // is the 3-6 px outside it, so the gradient stays strong until
                // the very edge instead of peaking only under the chip.
                GradientStop {
                    position: 0.0
                    color: Colors.withAlpha(Colors.primary, 0.45)
                }
                GradientStop {
                    position: 0.65
                    color: Colors.withAlpha(Colors.primary, 0.42)
                }
                GradientStop {
                    position: 0.85
                    color: Colors.withAlpha(Colors.primary, 0.18)
                }
                GradientStop {
                    position: 1.0
                    color: Colors.withAlpha(Colors.primary, 0.0)
                }
            }

            PathRectangle {
                width: root.haloSize
                height: root.haloSize
                radius: root.haloSize / 2
            }
        }
    }

    // A crisp ring on top of the soft halo. The pill covers its centre; the
    // expanding edge is what makes the pulse readable in the 3 px strip
    // margins. It is capped at 1.2 so the stroke stays inside the bar.
    Shape {
        id: ring

        anchors.fill: parent
        opacity: 0
        visible: opacity > 0.001
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Colors.withAlpha(Colors.primary, 0.65)
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin

            PathRectangle {
                width: ring.width
                height: ring.height
                radius: ring.height / 2
            }
        }
    }

    Rectangle {
        id: sweep

        x: -width
        // The last two rows of the strip. The chip is vertically centered in
        // the bar, so its top sits (barHeight - chipHeight) / 2 below the
        // strip's top.
        y: Dimensions.bar.height - height
            - (Dimensions.bar.height - root.height) / 2
        width: root.sweepLength
        height: 2
        radius: 1
        opacity: 0
        visible: opacity > 0.001

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Colors.withAlpha(Colors.primary, 1.0)
            }
            GradientStop {
                position: 0.45
                color: Colors.withAlpha(Colors.primary, 0.5)
            }
            GradientStop {
                position: 1.0
                color: Colors.withAlpha(Colors.primary, 0.0)
            }
        }
    }

    ParallelAnimation {
        id: bloom

        // Halo: quick fade in, slow expansion, then dissolve.
        SequentialAnimation {
            PropertyAction { target: halo; property: "scale"; value: 0.75 }
            PropertyAction { target: halo; property: "opacity"; value: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: halo
                    property: "scale"
                    to: 1.12
                    duration: root.haloDuration
                    easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: halo
                        property: "opacity"
                        to: 1.0
                        duration: 70
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: halo
                        property: "opacity"
                        to: 0.0
                        duration: root.haloDuration - 70
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Ring: the soft halo's crisp companion. It starts inside the pill so
        // the first visible edge is already moving outwards.
        SequentialAnimation {
            PropertyAction { target: ring; property: "scale"; value: 0.95 }
            PropertyAction { target: ring; property: "opacity"; value: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: ring
                    property: "scale"
                    to: 1.20
                    duration: root.haloDuration
                    easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: ring
                        property: "opacity"
                        to: 0.9
                        duration: 50
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ring
                        property: "opacity"
                        to: 0.0
                        duration: root.haloDuration - 50
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Bar-edge streak: the bright head leaves the chip, crosses the whole
        // bar and fades only as it reaches the opposite edge.
        SequentialAnimation {
            PauseAnimation { duration: root.sweepDelay }
            PropertyAction { target: sweep; property: "x"; value: -sweep.width }
            PropertyAction { target: sweep; property: "opacity"; value: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: sweep
                    property: "x"
                    to: -sweep.width - root.sweepDistance
                    duration: root.sweepDuration
                    easing.type: Easing.InOutCubic
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: sweep
                        property: "opacity"
                        to: 0.9
                        duration: 60
                        easing.type: Easing.OutCubic
                    }
                    PauseAnimation { duration: root.sweepDuration - 360 }
                    NumberAnimation {
                        target: sweep
                        property: "opacity"
                        to: 0.0
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
