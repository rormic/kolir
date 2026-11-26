import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../theme"
import "../../services"

// Sound sheet for the volume pill. The surface, scrim, reveal and dismissal
// come from EmbeddedSheet (mirrored like the night-light sheet); this file
// owns the controls and sizes the panel to them. Left click opens it, Escape
// or an outside click closes it. Device/volume actions stay on AudioService.
EmbeddedSheet {
    id: root

    mirror: true

    // The sheet grows to fit every control (no outer scrolling) and is clamped
    // so it never runs past the bottom of the screen. These tokens mirror the
    // content layout below.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 10
    // Extra breathing room below the last control, so the settled sheet keeps
    // the same bottom gap as the fixed-height night-light sheet.
    readonly property int contentBottomReserve: 6
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + controls.contentHeight + root.contentBottomReserve)

    // The sheet is sized to its controls, so a device or codec arriving after
    // the reveal grows the panel instead of clipping the list. Fade that
    // growth in rather than jumping.
    Behavior on panelHeight {
        enabled: root.opened

        NumberAnimation {
            duration: Motion.move
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedCurve
        }
    }

    readonly property string statusText: {
        const out = AudioService.activeSink;
        if (!out || !out.description)
            return "No output device";

        return AudioService.muted ? "Muted · " + out.description : out.description;
    }

    function open() {
        if (root.opened)
            return;

        controls.refresh();
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
        target: "volume"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
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
            title: "Sound"
            subtitle: root.statusText
        }

        SoundControls {
            id: controls

            Layout.fillWidth: true
            Layout.preferredHeight: controls.contentHeight
        }
    }
}
