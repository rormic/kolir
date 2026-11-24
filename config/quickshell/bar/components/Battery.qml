import QtQuick
import "../../services"
import "../../theme"

// Battery chip: level icon plus percentage, with a bolt while charging.
//
// The chip only takes space where a battery belongs. Desktops have no
// UPower battery and a non-portable chassis, so it stays hidden; a laptop with
// no usable pack still shows the alert glyph and turns the icon red, so a
// missing, dead or not-yet-reported battery never fails silently.
//
// When the charger connects, BatteryService emits `chargerConnected` and this
// component plays a one-shot bloom: a soft primary halo and an expanding ring
// behind the pill, a short streak along the bar's bottom edge and a small
// scale pulse. The state already present at shell start is silent, so logging
// in while plugged in does not replay it.
Item {
    id: root

    signal activated()

    // Bound by Bar to the embedded battery sheet's modal state.
    property bool popupActive: false

    visible: BatteryService.expected
    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Set by Bar.qml to the chip's distance from the bar's left edge, so the
    // streak crosses the whole bar. The default keeps a standalone preview
    // readable.
    property real sweepDistance: 240

    // Behind the pill: the pill clips its own children, so the halo and the
    // streak must be siblings rather than children of the Pill.
    ChargeBloom {
        id: bloom

        anchors.fill: parent
        sweepDistance: root.sweepDistance
    }

    Item {
        id: chipScale

        anchors.fill: parent

        Pill {
            id: chip

            anchors.fill: parent

            function chargeIcon(percent, charging) {
                if (charging) {
                    if (percent >= 90)
                        return Icons.batteryChargingFull;
                    if (percent >= 80)
                        return Icons.batteryCharging80;
                    if (percent >= 60)
                        return Icons.batteryCharging60;
                    if (percent >= 50)
                        return Icons.batteryCharging50;
                    if (percent >= 30)
                        return Icons.batteryCharging30;
                    return Icons.batteryCharging20;
                }

                if (percent >= 95)
                    return Icons.batteryFull;
                if (percent >= 80)
                    return Icons.battery6Bar;
                if (percent >= 60)
                    return Icons.battery5Bar;
                if (percent >= 45)
                    return Icons.battery4Bar;
                if (percent >= 30)
                    return Icons.battery3Bar;
                if (percent >= 15)
                    return Icons.battery2Bar;
                if (percent >= 5)
                    return Icons.battery1Bar;
                return Icons.battery0Bar;
            }

            icon: BatteryService.present
                ? chip.chargeIcon(BatteryService.percentage, BatteryService.charging)
                : Icons.batteryMissing
            iconColor: !BatteryService.present || BatteryService.low
                ? Colors.error
                : BatteryService.charging
                    ? Colors.primary
                    : Colors.onSurfaceVariant
            text: BatteryService.present ? BatteryService.percentage + "%" : ""
            textSize: Typography.size.labelMedium
            textColor: BatteryService.low ? Colors.error : Colors.onSurface
            surfaceColor: Colors.surfaceContainerHigh
            spacing: 4
            active: root.popupActive

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated()
            }
        }
    }

    Connections {
        target: BatteryService

        function onChargerConnected() {
            bloom.play();
            pulse.restart();
        }
    }

    // The pulse lives on the wrapper, not on the Pill: Pill.scale is already
    // bound to hover, and replacing that binding would break the hover
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
