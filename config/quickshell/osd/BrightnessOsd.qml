import QtQuick
import Quickshell
import "../theme"

Scope {
    Connections {
        target: BrightnessService
        function onBrightnessChangedManually(val) {
            osd.show();
        }
    }

    OsdPanel {
        id: osd

        layerNamespace: "brightness-osd"

        icon: BrightnessService.value < 34
            ? Icons.brightnessLow
            : (BrightnessService.value < 67
                ? Icons.brightnessMedium
                : Icons.brightnessHigh)
        iconColor: Colors.primary

        value: BrightnessService.value
        indicatorColor: Colors.primary

        text: BrightnessService.value + "%"
        textColor: Colors.onSurface
    }
}
