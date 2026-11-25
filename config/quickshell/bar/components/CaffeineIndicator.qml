import QtQuick
import "../../services"
import "../../theme"

// Caffeine status: a flat readout that is also its own off switch.
//
// It only takes space while the session is being kept awake; timed sessions
// also show the remaining time. Clicking the status turns keep-awake off, and
// because the item would otherwise vanish under the pointer with no answer, it
// holds for a beat struck through and labelled "Off" before fading away. The
// switch and the duration presets still live in Settings.
StatusItem {
    id: root

    // How long the "Off" answer stays on the strip before the status collapses.
    readonly property int offHoldDuration: 1200

    // True from the click until the off answer has faded out, so the status
    // outlives the service state it reports.
    property bool holdingOff: false

    visible: CaffeineService.enabled || root.holdingOff

    icon: Icons.caffeine
    iconStruck: root.holdingOff
    iconColor: CaffeineService.enabled ? Colors.primary : Colors.onSurfaceVariant
    text: CaffeineService.enabled
        ? (CaffeineService.timed ? CaffeineService.shortLabel : "")
        : "Off"
    textColor: Colors.onSurfaceVariant

    // A click turns keep-awake off. The second click during the hold is
    // ignored: the status is already gone, and re-enabling lives in Settings.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.turnOff()
    }

    // The click handler, split out so the off answer can also be driven
    // directly (an IPC test, a future keyboard shortcut).
    function turnOff() {
        if (root.holdingOff || !CaffeineService.enabled)
            return;

        CaffeineService.disable();
        root.holdingOff = true;
        offFeedback.restart();
    }

    // Power-down answer: the struck status holds for a beat, then dims and
    // sinks instead of simply disappearing under the pointer.
    SequentialAnimation {
        id: offFeedback

        PauseAnimation { duration: root.offHoldDuration }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0
                duration: Motion.listExit
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: root
                property: "scale"
                to: 0.9
                duration: Motion.listExit
                easing.type: Easing.OutCubic
            }
        }

        ScriptAction {
            script: {
                // Hide before restoring, or the status flashes back for a frame.
                root.holdingOff = false;
                root.opacity = 1;
                root.scale = 1;
            }
        }
    }

    // Keep-awake switched back on from Settings during the hold (for example a
    // preset click): drop the off answer and show the live status instead.
    Connections {
        target: CaffeineService

        function onEnabledChanged() {
            if (!CaffeineService.enabled || !root.holdingOff)
                return;

            offFeedback.stop();
            root.holdingOff = false;
            root.opacity = 1;
            root.scale = 1;
        }
    }
}
