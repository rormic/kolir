import QtQuick
import "../../theme"
import "../../services"

// Brightness chip: neon icon, progress accent bar. The night-light sheet is
// owned by Bar (it lives in the bar surface), so the chip only reports left
// clicks through `activated`.
Pill {
    id: root

    signal activated()

    // Bound by Bar to the embedded popup's modal state.
    property bool popupActive: false

    implicitWidth: 68
    visible: BrightnessService.available

    icon: BrightnessService.value < 34
        ? Icons.brightnessLow
        : BrightnessService.value < 67
            ? Icons.brightnessMedium
            : Icons.brightnessHigh
    iconColor: Colors.primary
    text: BrightnessService.value + "%"
    textSize: Typography.size.labelMedium
    textColor: Colors.onSurface
    surfaceColor: Colors.surfaceContainerHigh
    spacing: 4
    active: root.popupActive

    // A subtle tertiary ring while the blue-light filter is active. The
    // normal primary ring still wins on hover and while the popup is open.
    borderColor: hovered || active
        ? Colors.withAlpha(Colors.primary, 0.55)
        : HyprsunsetService.enabled
            ? Colors.withAlpha(Colors.tertiary, 0.4)
            : Colors.withAlpha(Colors.outlineVariant, 0.18)

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) BrightnessService.adjust(5);
            else if (wheel.angleDelta.y < 0) BrightnessService.adjust(-5);
        }
    }

    // Material 3 linear progress indicator along the bottom edge.
    ProgressIndicator {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 6
            rightMargin: 6
            bottomMargin: 2
        }
        height: implicitHeight
        value: BrightnessService.value
        indicatorColor: Colors.primary
        trackColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)
    }
}
