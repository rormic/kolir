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

    // Bound by Bar to the other embedded sheets. The pill tooltip is drawn
    // below the bar strip, so it must not float over an open sheet while the
    // pointer happens to rest on the chip.
    property bool overlayOpen: false

    readonly property bool nightLightOn: HyprsunsetService.enabled
        && HyprsunsetService.available

    implicitWidth: 68
    visible: BrightnessService.available
    // The night-light tooltip hangs below the pill, so the surface itself must
    // not clip its children.
    clip: false

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

    // A tertiary ring while the blue-light filter is active. It stays put on
    // hover (the pill still scales and the tooltip appears) so the colour
    // keeps meaning "filter on"; only an open popup swaps in the primary ring.
    borderColor: active
        ? Colors.withAlpha(Colors.primary, 0.55)
        : nightLightOn
            ? Colors.withAlpha(Colors.tertiary, 0.6)
            : hovered
                ? Colors.withAlpha(Colors.primary, 0.55)
                : Colors.withAlpha(Colors.outlineVariant, 0.18)
    // A slightly heavier stroke makes the active filter readable at a glance
    // without turning the chip into a second accent colour.
    borderWidth: nightLightOn ? 1.5 : 1

    Behavior on borderWidth {
        NumberAnimation { duration: Motion.hover }
    }

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

    // Active-outline hint. The swatch repeats the pill's tertiary stroke, so
    // the tooltip explains the ring with colour as well as with words.
    Rectangle {
        id: nightLightTooltip

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + Dimensions.spacing.small
        z: 10
        visible: root.hovered && !root.popupActive && !root.overlayOpen
            && root.nightLightOn
        width: tooltipContent.implicitWidth + Dimensions.padding.chipHorizontal * 2
        height: tooltipContent.implicitHeight + Dimensions.spacing.small * 2
        radius: Dimensions.radius.small
        color: Colors.surfaceContainerHighest
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

        Item {
            id: tooltipContent

            anchors.centerIn: parent
            implicitWidth: tooltipSwatch.width + Dimensions.spacing.small
                + tooltipLabels.width
            implicitHeight: Math.max(tooltipSwatch.height,
                tooltipLabels.implicitHeight)

            Rectangle {
                id: tooltipSwatch

                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 12
                radius: Dimensions.radius.full
                color: Colors.withAlpha(Colors.tertiary, 0.1)
                border.width: 1
                border.color: Colors.withAlpha(Colors.tertiary, 0.6)
            }

            Column {
                id: tooltipLabels

                anchors.verticalCenter: parent.verticalCenter
                x: tooltipSwatch.width + Dimensions.spacing.small
                spacing: 0

                Text {
                    text: "Night light on"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    font.weight: Typography.weight.bold
                }

                Text {
                    text: HyprsunsetService.temperature + " K · blue-light filter"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    font.weight: Typography.weight.regular
                }
            }
        }
    }
}
