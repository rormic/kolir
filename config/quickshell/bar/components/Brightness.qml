import QtQuick
import "../../theme"
import "../../services"

// Brightness chip: neon icon, progress accent bar. The night-light sheet is
// owned by Bar (it lives in the bar surface), so the chip only reports left
// clicks through `activated`. While that sheet is open the chip stretches over
// its width and becomes its header (see HeaderPill).
HeaderPill {
    id: root

    // Bound by Bar to the other embedded sheets. The pill tooltip is drawn
    // below the bar strip, so it must not float over an open sheet while the
    // pointer happens to rest on the chip.
    property bool overlayOpen: false

    readonly property bool nightLightOn: HyprsunsetService.enabled
        && HyprsunsetService.available

    // The sheet's title block lives here now, so the chip owns its status line.
    readonly property string nightLightStatus: {
        if (!HyprsunsetService.available)
            return "hyprsunset is not running";

        const state = HyprsunsetService.enabled ? "On" : "Off";
        let text = state + " · " + HyprsunsetService.temperature + " K";

        if (HyprsunsetService.scheduleActive && HyprsunsetService.scheduleLabel !== "")
            text += " · " + HyprsunsetService.scheduleLabel;

        return text;
    }

    implicitWidth: 68
    // A machine without a brightness backend hides the chip, but the sheet can
    // still be opened over IPC and must keep its header.
    visible: BrightnessService.available || root.headerMode
    interactive: BrightnessService.available

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

    progressValue: BrightnessService.value
    progressColor: Colors.primary

    adjust: step => BrightnessService.adjust(step * 5)

    headerIcon: Icons.nightlight
    headerTitle: "Night Light"
    headerStatus: root.nightLightStatus
    headerStatusColor: HyprsunsetService.available
        ? Colors.onSurfaceVariant
        : Colors.error

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
