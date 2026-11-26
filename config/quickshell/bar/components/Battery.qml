import QtQuick
import "../../services"
import "battery"

// Battery chip: the gauge face plus the charge bloom.
//
// The chip only takes space where a battery belongs. Desktops have no UPower
// battery and a non-portable chassis, so it stays hidden; a laptop with no
// usable pack still shows the alert glyph, so a missing, dead or
// not-yet-reported battery never fails silently.
//
// When the charger connects, BatteryService emits `chargerConnected` and this
// component plays a one-shot bloom: a soft primary halo and an expanding ring
// behind the chip, a short streak along the bar's bottom edge and a small
// scale pulse. The state already present at shell start is silent, so logging
// in while plugged in does not replay it.
Item {
    id: root

    signal activated()

    // Bound by Bar to the embedded battery sheet's modal state.
    property bool popupActive: false

    visible: BatteryService.expected
    implicitWidth: gauge.implicitWidth
    implicitHeight: gauge.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Set by Bar.qml to the chip's distance from the bar's left edge, so the
    // streak crosses the whole bar. The default keeps a standalone preview
    // readable.
    property real sweepDistance: 240

    // Behind the chip: the halo and the streak must be siblings rather than
    // children of the gauge, which clips its own content.
    ChargeBloom {
        id: bloom

        anchors.fill: parent
        sweepDistance: root.sweepDistance
    }

    Item {
        id: chipScale

        anchors.fill: parent

        BatteryGauge {
            id: gauge

            anchors.fill: parent
            level: BatteryService.percentage
            present: BatteryService.present
            charging: BatteryService.charging
            low: BatteryService.low
            active: root.popupActive
            onActivated: root.activated()
        }
    }

    Connections {
        target: BatteryService

        function onChargerConnected() {
            bloom.play();
            pulse.restart();
        }
    }

    // The pulse lives on the wrapper, not on the gauge: BatteryGauge.scale is
    // already bound to hover, and replacing that binding would break the hover
    // feedback. Scaling the wrapper multiplies the two effects.
    SequentialAnimation {
        id: pulse

        NumberAnimation {
            target: chipScale
            property: "scale"
            to: 1.06
            duration: 130
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: chipScale
            property: "scale"
            to: 1.0
            duration: 340
            easing.type: Easing.OutCubic
        }
    }
}
