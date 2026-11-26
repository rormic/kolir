import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../theme"
import "../../services"
import "battery"

// Battery sheet for the battery pill. The surface, scrim, reveal and dismissal
// come from EmbeddedSheet (mirrored like the other right-edge sheets); this
// file owns the content-driven height and the IPC entry points. Left click
// opens it, Escape or an outside click closes it. BatteryService stays the
// only UPower reader; BatteryDetails only formats its values.
EmbeddedSheet {
    id: root

    mirror: true

    // The sheet grows to fit the hero card and the optional detail rows, and
    // is clamped so it never runs past the bottom of the screen. These tokens
    // mirror the content layout below.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 12
    // Extra breathing room below the last card, matching the sound sheet.
    readonly property int contentBottomReserve: 6
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + details.implicitHeight + root.contentBottomReserve)

    // The detail rows appear and disappear with UPower's estimates, so fade
    // the height change instead of jumping.
    Behavior on panelHeight {
        enabled: root.opened

        NumberAnimation {
            duration: Motion.move
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedCurve
        }
    }

    function open() {
        if (root.opened)
            return;

        root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        root.revealClose();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    onDismissalRequested: root.close()

    Keys.onEscapePressed: function (event) {
        root.close();
        event.accepted = true;
    }

    IpcHandler {
        target: "battery"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function status(): string {
            return JSON.stringify({
                open: root.opened,
                modal: root.modal,
                present: BatteryService.present,
                expected: BatteryService.expected,
                percentage: BatteryService.percentage,
                state: BatteryService.chargeState,
                low: BatteryService.low,
                plugged: BatteryService.plugged,
                timeToEmpty: BatteryService.timeToEmpty,
                timeToFull: BatteryService.timeToFull,
                powerDraw: BatteryService.powerDraw,
                energy: BatteryService.energy,
                energyCapacity: BatteryService.energyCapacity,
                healthSupported: BatteryService.healthSupported,
                health: BatteryService.health
            });
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + root.contentColumnMargins
            leftMargin: root.contentColumnMargins
            rightMargin: root.contentColumnMargins
            bottomMargin: root.contentColumnMargins
        }
        spacing: root.contentColumnSpacing

        PopupHeader {
            Layout.fillWidth: true
            Layout.preferredHeight: root.titleBlockHeight
            title: "Battery"
            subtitle: details.statusText
            subtitleColor: details.alert ? Colors.error : Colors.onSurfaceVariant
        }

        BatteryDetails {
            id: details

            Layout.fillWidth: true
            active: root.opened
        }
    }
}
