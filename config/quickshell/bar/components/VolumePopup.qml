import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import "../../theme"
import "../../services"

// Sound popout for the volume pill. Like SettingsMenu and BrightnessPopup it
// is drawn inside the bar's own layer surface instead of a separate popup
// window, mirrored to the right edge and flush with the physical screen edge,
// so while it is open it covers the decorative frame ring and the compositor's
// active-window border. Left click opens it; Escape or an outside click closes
// it. Device/volume actions stay on AudioService.
Item {
    id: root

    // A closed sheet must not exist for input purposes: a full-window
    // dismissal MouseArea left in the tree kept winning Qt's cursor lookup,
    // so the settings rows never got their pointing-hand cursor.
    visible: root.opened || root.reveal > 0.001

    property bool opened: false

    // 0 = hidden, 1 = fully visible. Only this surface is animated; the bar
    // window itself never resizes.
    property real reveal: 0

    // Exposed for the bar input mask and the chip highlight. While the sheet
    // is open the whole bar surface becomes modal so an outside click can
    // dismiss it even though the panel lives in the bar surface.
    readonly property bool modal: root.opened || root.reveal > 0.001

    readonly property int popupWidth: 424

    // The sheet grows to fit every control (no outer scrolling) and is
    // clamped so it never runs past the bottom of the screen. These three
    // tokens mirror the content layout below.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 10
    // Extra breathing room below the last control, so the settled sheet keeps
    // the same bottom gap as the fixed-height night-light sheet.
    readonly property int contentBottomReserve: 6
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)
    readonly property int panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + controls.contentHeight + root.contentBottomReserve)

    // Same mirrored geometry as BrightnessPopup: the body keeps `panelFlare`
    // away from the shoulder side (left here) and runs to the physical right
    // screen edge, covering the frame ring and the window border while open.
    readonly property int panelFlare: 32
    readonly property int panelBottomRadius: Dimensions.radius.extraLarge
    readonly property int panelMelt: Dimensions.radius.extraExtraLarge
    readonly property int panelShoulderRadius: root.panelBottomRadius
    readonly property int panelShoulderDrop: Dimensions.frame.thickness + root.panelShoulderRadius
    readonly property int contentTopInset: root.panelShoulderDrop + 8
    readonly property int contentLeftInset: root.panelFlare
    readonly property int contentRightInset: Dimensions.frame.thickness

    readonly property string statusText: {
        const out = AudioService.activeSink;
        if (!out || !out.description)
            return "No output device";

        return AudioService.muted ? "Muted · " + out.description : out.description;
    }

    // The sheet grows out of the corner: width first, then height, so it does
    // not appear as a full-height blind dropping from the bar.
    readonly property real revealWidth: Math.min(1, root.reveal * 1.35)
    readonly property real panelShapeWidth: Math.max(
        2 * root.panelFlare + 80, root.popupWidth * root.revealWidth)
    readonly property real contentReveal: Math.max(
        0, Math.min(1, (root.reveal - 0.65) / 0.35))
    // Rounded body of the sheet. Keep the contour valid while the panel is
    // only a few pixels tall.
    readonly property real panelBodyHeight: Math.max(
        root.panelShoulderDrop + root.panelBottomRadius + 16,
        root.panelHeight * root.reveal)
    // The pour grows in once the sheet has dropped, so it never stretches the
    // opening animation into a long tail.
    readonly property real panelMeltHeight: root.panelMelt * root.contentReveal
    readonly property real panelShapeHeight: root.panelBodyHeight + root.panelMeltHeight

    // Right-aligned mirror of the panel fill path: `br` is the body right edge
    // at the physical screen edge, `bl` the body left edge under the shoulder,
    // and the bottom-right corner bends down into that same edge.
    readonly property string panelFillPath: {
        const w = root.panelShapeWidth;
        const h = root.panelBodyHeight;
        const m = root.panelMeltHeight;
        const r = root.panelBottomRadius;
        const sr = root.panelShoulderRadius;
        const top = Dimensions.frame.thickness;
        const br = w;
        const bl = root.panelFlare;
        return `M ${br} 0 H ${bl - sr} V ${top}`
            + ` A ${sr} ${sr} 0 0 1 ${bl} ${top + sr} V ${h - r}`
            + ` Q ${bl} ${h} ${bl + r} ${h} H ${br - m}`
            + ` C ${br - m * 0.375} ${h} ${br} ${h} ${br} ${h + m}`
            + ` V 0 Z`;
    }

    focus: root.opened

    function open() {
        if (root.opened)
            return;

        revealAnim.stop();
        settleTimer.stop();
        root.opened = true;
        root.reveal = 0;
        root.forceActiveFocus();

        // The device/codec model populates asynchronously after refresh(), so
        // wait for it to settle before revealing; otherwise the panel would
        // resize (or need scrolling) halfway through the opening animation.
        controls.refresh();
        settleTimer.start();
    }

    function close() {
        if (!root.opened)
            return;

        settleTimer.stop();
        root.opened = false;
        revealAnim.stop();

        if (root.reveal <= 0.01) {
            root.reveal = 0;
            return;
        }

        root.animateReveal(0, 160, Easing.InCubic);
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    function animateReveal(to, duration, easing) {
        revealAnim.stop();
        revealAnim.to = to;
        revealAnim.duration = duration;
        revealAnim.easing.type = easing;
        revealAnim.start();
    }

    Keys.onEscapePressed: function (event) {
        root.close();
        event.accepted = true;
    }

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        duration: 240
        easing.type: Easing.OutQuint

        onFinished: {
            if (!root.opened && root.reveal <= 0.01)
                root.reveal = 0;
        }
    }

    // Starts the reveal once the audio model has settled (see open()).
    Timer {
        id: settleTimer

        interval: 320
        repeat: false
        onTriggered: {
            if (root.opened && root.reveal <= 0.001)
                root.animateReveal(1, 240, Easing.OutQuint);
        }
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

    // Full-window dismissal layer. The bar input mask expands to the whole
    // screen while the sheet is open, so this catches any click outside the
    // panel. It sits below the panel itself.
    MouseArea {
        id: dismissArea

        anchors.fill: parent
        enabled: root.modal
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: 0
        onClicked: root.close()
    }

    // Panel viewport. Its height is the revealed part of the panel; the page
    // tree inside keeps its final size, so opening never resquashes the layout.
    Item {
        id: popout

        x: root.width - root.panelShapeWidth
        y: Dimensions.bar.height
        width: root.panelShapeWidth
        // Ends exactly at the bottom of the pour so the sheet still collapses
        // cleanly while closing.
        height: Math.max(0, root.panelHeight * root.reveal + root.panelMeltHeight)
        visible: root.opened || root.reveal > 0.001
        clip: true
        z: 10

        Item {
            id: panelBody

            width: root.popupWidth
            height: root.panelHeight

            Shape {
                width: parent.width
                height: root.panelShapeHeight
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Colors.surfaceContainerLow
                    strokeWidth: 0

                    PathSvg {
                        path: root.panelFillPath
                    }
                }
            }

            // Swallow clicks on empty panel areas so they do not fall through
            // to the full-window dismissal layer and close the sheet.
            MouseArea {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: root.panelShoulderDrop
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                z: 0
            }

            MouseArea {
                anchors {
                    fill: parent
                    leftMargin: root.contentLeftInset
                    rightMargin: root.contentRightInset
                }
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                z: 0
            }

            Item {
                id: content

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    topMargin: root.contentTopInset
                    leftMargin: root.contentLeftInset
                    rightMargin: root.contentRightInset
                }
                opacity: root.contentReveal
                transform: Translate { y: (1.0 - root.contentReveal) * -10 }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: root.contentColumnMargins
                    }
                    spacing: root.contentColumnSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.titleBlockHeight
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: "Sound"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleLarge
                            font.weight: Typography.weight.bold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.statusText
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }
                    }

                    SoundControls {
                        id: controls

                        Layout.fillWidth: true
                        Layout.preferredHeight: controls.contentHeight
                    }
                }
            }
        }
    }
}
