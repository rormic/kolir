import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../theme"
import "../../../services"
import ".."

// Detail content for the embedded battery sheet: the hero percentage with the
// wavy charge bar, the power/energy/health rows UPower can provide, and the
// missing-battery explanation.
//
// Every value defaults to BatteryService but stays writable, so a throwaway
// Quickshell config can preview charging, low, full and missing states without
// a real pack. The raw UPower units (seconds, watts, watt-hours) are formatted
// here; BatteryService only mirrors the display device.
ColumnLayout {
    id: root

    property bool present: BatteryService.present
    property int percentage: BatteryService.percentage
    property int chargeState: BatteryService.chargeState
    property bool low: BatteryService.low
    property bool plugged: BatteryService.plugged
    property real timeToEmpty: BatteryService.timeToEmpty
    property real timeToFull: BatteryService.timeToFull
    property real powerDraw: BatteryService.powerDraw
    property real energy: BatteryService.energy
    property real energyCapacity: BatteryService.energyCapacity
    property bool healthSupported: BatteryService.healthSupported
    property real health: BatteryService.health

    // The host sheet stops the wave while it is closed, so an idle popup
    // schedules no frames. A standalone preview keeps it running.
    property bool active: true

    spacing: 12

    readonly property bool charging: root.chargeState === UPowerDeviceState.Charging
        || root.chargeState === UPowerDeviceState.PendingCharge
    readonly property bool alert: !root.present || root.low

    readonly property bool showPower: root.present
        && isFinite(root.powerDraw) && Math.abs(root.powerDraw) >= 0.05
    readonly property bool showEnergy: root.present
        && isFinite(root.energy) && isFinite(root.energyCapacity)
        && root.energyCapacity > 0
    readonly property bool showHealth: root.present && root.healthSupported
        && isFinite(root.health)
    readonly property bool showDetails: root.showPower || root.showEnergy
        || root.showHealth

    readonly property string stateLabel: {
        switch (root.chargeState) {
        case UPowerDeviceState.Charging:
            return "Charging";
        case UPowerDeviceState.Discharging:
            return "Discharging";
        case UPowerDeviceState.Empty:
            return "Empty";
        case UPowerDeviceState.FullyCharged:
            return "Fully charged";
        case UPowerDeviceState.PendingCharge:
            return "Charge pending";
        case UPowerDeviceState.PendingDischarge:
            return "Discharge pending";
        default:
            return "Unknown";
        }
    }

    readonly property string timeLabel: {
        if (!root.present)
            return "";

        if (root.charging) {
            if (root.timeToFull > 0 && isFinite(root.timeToFull))
                return root.formatDuration(root.timeToFull) + " until full";
            return "";
        }

        if (root.chargeState === UPowerDeviceState.Discharging
                || root.chargeState === UPowerDeviceState.PendingDischarge) {
            if (root.timeToEmpty > 0 && isFinite(root.timeToEmpty))
                return root.formatDuration(root.timeToEmpty) + " remaining";
            return "";
        }

        if (root.chargeState === UPowerDeviceState.FullyCharged && root.plugged)
            return "plugged in";

        return "";
    }

    readonly property string statusText: {
        if (!root.present)
            return "Not detected";

        const state = root.low ? "Low battery" : root.stateLabel;
        return root.timeLabel !== "" ? state + " · " + root.timeLabel : state;
    }

    function formatDuration(seconds) {
        const totalMinutes = Math.round(seconds / 60);
        if (totalMinutes < 1)
            return "less than a minute";

        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;

        if (hours <= 0)
            return minutes + " min";
        if (minutes === 0)
            return hours + " h";
        return hours + " h " + minutes + " min";
    }

    function formatPower(watts) {
        return isFinite(watts) ? Math.abs(watts).toFixed(1) + " W" : "—";
    }

    function formatEnergy(wattHours) {
        return isFinite(wattHours) ? wattHours.toFixed(1) : "—";
    }

    // ── Hero: level and charge bar ────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.present
        implicitHeight: hero.implicitHeight + 32
        radius: Dimensions.radius.medium
        color: Colors.surfaceContainerHigh
        border.width: 1
        border.color: root.alert
            ? Colors.withAlpha(Colors.error, 0.35)
            : Colors.withAlpha(Colors.outlineVariant, 0.22)

        Behavior on border.color {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }

        ColumnLayout {
            id: hero

            anchors {
                fill: parent
                margins: 16
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.percentage + "%"
                    color: root.alert
                        ? Colors.error
                        : root.charging
                            ? Colors.primary
                            : Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: 36
                    font.weight: Typography.weight.bold

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.color
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.standardDecelerateCurve
                        }
                    }
                }

                Text {
                    visible: root.charging
                    Layout.alignment: Qt.AlignVCenter
                    text: Icons.bolt
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.extraLarge
                }

                Item { Layout.fillWidth: true }
            }

            ProgressIndicator {
                Layout.fillWidth: true
                wavy: true
                value: root.percentage
                indicatorColor: root.alert ? Colors.error : Colors.primary
                playing: root.active
            }
        }
    }

    // ── Detail rows ───────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.showDetails
        implicitHeight: detailsColumn.implicitHeight + 28
        radius: Dimensions.radius.medium
        color: Colors.surfaceContainerHigh
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

        ColumnLayout {
            id: detailsColumn

            anchors {
                fill: parent
                margins: 14
            }
            spacing: 0

            DetailRow {
                Layout.fillWidth: true
                visible: root.showPower
                icon: Icons.bolt
                label: root.charging ? "Charge power" : "Power draw"
                value: root.formatPower(root.powerDraw)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: root.showPower && (root.showEnergy || root.showHealth)
                color: Colors.withAlpha(Colors.outlineVariant, 0.14)
            }

            DetailRow {
                Layout.fillWidth: true
                visible: root.showEnergy
                icon: Icons.batteryFull
                label: "Energy"
                value: root.formatEnergy(root.energy) + " / "
                    + root.formatEnergy(root.energyCapacity) + " Wh"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: root.showEnergy && root.showHealth
                color: Colors.withAlpha(Colors.outlineVariant, 0.14)
            }

            DetailRow {
                Layout.fillWidth: true
                visible: root.showHealth
                icon: Icons.monitorHeart
                label: "Health"
                value: Math.round(root.health) + "%"
            }
        }
    }

    // ── Missing battery ───────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: !root.present
        implicitHeight: missingRow.implicitHeight + 32
        radius: Dimensions.radius.medium
        color: Colors.surfaceContainerHigh
        border.width: 1
        border.color: Colors.withAlpha(Colors.error, 0.35)

        RowLayout {
            id: missingRow

            anchors {
                fill: parent
                margins: 16
            }
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                radius: Dimensions.radius.small + 2
                color: Colors.withAlpha(Colors.error, 0.14)

                Text {
                    anchors.centerIn: parent
                    text: Icons.batteryMissing
                    color: Colors.error
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.extraLarge
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "No internal battery"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.bodyMedium
                    font.weight: Typography.weight.medium
                }

                Text {
                    Layout.fillWidth: true
                    text: "UPower does not report a usable battery on this device."
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component DetailRow: RowLayout {
        id: detailRow

        property string icon: ""
        property string label: ""
        property string value: ""

        spacing: 10
        implicitHeight: 30

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: detailRow.icon
            color: Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.medium
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: detailRow.label
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: detailRow.value
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
        }
    }
}
