import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import "../../theme"
import "../../services"
import "nightLight"

// Night-light popout for the brightness pill. Like SettingsMenu it is drawn
// inside the bar's own layer surface instead of a separate popup window, but
// mirrored to the right edge: the sheet hangs below the strip, keeps its body
// on the inner frame edge and melts into the right frame ring, while the
// concave shoulder sits on its left. Left click opens it; Escape or an outside
// click closes it. The hyprsunset IPC stays on HyprsunsetService.
Item {
    id: root

    property bool opened: false

    // 0 = hidden, 1 = fully visible. Only this surface is animated; the bar
    // window itself never resizes.
    property real reveal: 0

    // Exposed for the bar input mask and the chip highlight. While the sheet
    // is open the whole bar surface becomes modal so an outside click can
    // dismiss it even though the panel lives in the bar surface.
    readonly property bool modal: root.opened || root.reveal > 0.001

    readonly property int popupWidth: 424
    readonly property int panelHeight: 540

    // Mirrored from SettingsMenu: the body keeps `panelFlare` away from the
    // shoulder side (left here). Its right edge goes all the way to the
    // physical screen edge, so while the sheet is open it also covers the
    // decorative frame ring and the compositor's active-window border. Both
    // use the same opaque `surfaceContainerLow`, so the seam disappears and
    // no foreign colour outlines the panel.
    readonly property int panelFlare: 32
    readonly property int panelBottomRadius: Dimensions.radius.extraLarge
    readonly property int panelMelt: Dimensions.radius.extraExtraLarge
    readonly property int panelShoulderRadius: root.panelBottomRadius
    readonly property int panelShoulderDrop: Dimensions.frame.thickness + root.panelShoulderRadius
    readonly property int contentTopInset: root.panelShoulderDrop + 8
    readonly property int contentLeftInset: root.panelFlare
    readonly property int contentRightInset: Dimensions.frame.thickness

    readonly property string statusText: {
        if (!HyprsunsetService.available)
            return "hyprsunset is not running";

        const state = HyprsunsetService.enabled ? "On" : "Off";
        let text = state + " · " + HyprsunsetService.temperature + " K";

        if (HyprsunsetService.scheduleActive && HyprsunsetService.scheduleLabel !== "")
            text += " · " + HyprsunsetService.scheduleLabel;

        return text;
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

    // Right-aligned mirror of SettingsMenu's panelFillPath. `br` is the body
    // right edge at the physical screen edge (covering the frame ring and the
    // window border), `bl` the body left edge under the shoulder, and the
    // bottom-right corner bends down into that same edge.
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
        root.opened = true;
        root.reveal = 0;
        root.forceActiveFocus();

        HyprsunsetService.refresh();
        if (HyprsunsetService.sunMode)
            HyprsunsetService.refreshLocation(false);

        root.animateReveal(1, 240, Easing.OutQuint);
    }

    function close() {
        if (!root.opened)
            return;

        temperatureCard.cancelDrag();
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

    IpcHandler {
        target: "nightLight"

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
                        margins: 14
                    }
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: "Night Light"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleLarge
                            font.weight: Typography.weight.bold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.statusText
                            color: HyprsunsetService.available
                                ? Colors.onSurfaceVariant
                                : Colors.error
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }
                    }

                    // Blue-light filter row, styled like the settings rows.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: filterRow.implicitHeight + 24
                        radius: Dimensions.radius.medium
                        color: Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                        RowLayout {
                            id: filterRow

                            anchors {
                                fill: parent
                                margins: 12
                            }
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                radius: Dimensions.radius.small + 2
                                color: HyprsunsetService.enabled
                                    ? Colors.primaryContainer
                                    : Colors.surfaceContainerHighest

                                Behavior on color { ColorAnimation { duration: 140 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.nightlight
                                    color: HyprsunsetService.enabled
                                        ? Colors.onPrimaryContainer
                                        : Colors.onSurfaceVariant
                                    font.family: Typography.iconFont
                                    font.pixelSize: Dimensions.icon.large
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: "Blue-light filter"
                                    color: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.bodyMedium
                                    font.weight: Typography.weight.medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Warm the display in the evening"
                                    color: Colors.onSurfaceVariant
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelSmall
                                    elide: Text.ElideRight
                                }
                            }

                            Toggle {
                                Layout.alignment: Qt.AlignVCenter
                                checked: HyprsunsetService.enabled
                                interactive: HyprsunsetService.available
                                onToggled: checked => HyprsunsetService.setEnabledManual(checked)
                            }
                        }
                    }

                    TemperatureCard {
                        id: temperatureCard

                        temperature: HyprsunsetService.temperature
                        minTemperature: HyprsunsetService.minTemperature
                        maxTemperature: HyprsunsetService.maxTemperature
                        interactive: HyprsunsetService.available
                        onTemperatureRequested: kelvin => HyprsunsetService.setTemperature(kelvin)
                    }

                    ScheduleCard {
                    }
                }
            }
        }
    }
}
