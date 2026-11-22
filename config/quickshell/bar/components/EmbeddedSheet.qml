import QtQuick
import QtQuick.Shapes
import "../../theme"

// Shared surface for the sheets embedded in the bar: the settings menu, the
// night-light sheet and the sound sheet all grow out of the bar strip as one
// connected surface instead of a separate popup window.
//
// This component owns the parts that must look and behave identically:
//   - the modal scrim over the desktop (the bar strip stays crisp),
//   - the pour-shaped panel, mirrored for the sheets anchored to the right,
//   - the corner reveal (width first, then height, content last) on the
//     Material 3 emphasized curves,
//   - the full-window dismissal layer, and
//   - the input area that swallows clicks on empty panel space.
//
// Subclasses own their content and their side effects. They drive the motion
// through `revealOpen()` / `revealClose()` from their own `open()` / `close()`
// and bound `panelHeight` (fixed, content driven, or morphed between pages).
Item {
    id: root

    // Body edge that is flush with the physical screen edge: false keeps the
    // body on the left (settings), true mirrors it to the right (night light,
    // sound). The shoulder and the pour follow the mirror.
    property bool mirror: false

    property bool opened: false
    // 0 = hidden, 1 = fully visible. Only this surface is animated; the bar
    // window itself never resizes.
    property real reveal: 0
    // Height of the visible panel, bound by the subclass.
    property real panelHeight: 0
    // Exposed for the bar input mask and the chip highlight.
    readonly property bool modal: opened || reveal > 0.001

    // A closed sheet must not exist for input purposes: a full-window
    // dismissal MouseArea left in the tree kept winning Qt's cursor lookup,
    // so the sheet underneath never got its pointing-hand cursor.
    visible: root.modal

    // Shared geometry. `panelFlare` is the distance from the shoulder side to
    // the body edge; the body runs to the physical screen edge on the mirrored
    // side, so while a sheet is open it covers the decorative frame ring and
    // the compositor's active-window border.
    readonly property int popupWidth: 424
    readonly property int panelFlare: 32
    readonly property int panelBottomRadius: Dimensions.radius.extraLarge
    readonly property int panelMelt: Dimensions.radius.extraExtraLarge
    readonly property int panelShoulderRadius: panelBottomRadius
    readonly property int panelShoulderDrop: Dimensions.frame.thickness + panelShoulderRadius
    readonly property int contentTopInset: panelShoulderDrop + 8
    readonly property int contentLeftInset: mirror ? panelFlare : Dimensions.frame.thickness
    readonly property int contentRightInset: mirror ? Dimensions.frame.thickness : panelFlare

    // The panel grows out of the bar corner: width first, then height, so it
    // does not appear as a full-width blind dropping from the strip.
    readonly property real revealWidth: Math.min(1, reveal * 1.35)
    readonly property real panelShapeWidth: Math.max(
        2 * panelFlare + 80, popupWidth * revealWidth)
    readonly property real contentReveal: Math.max(0, Math.min(1, (reveal - 0.65) / 0.35))
    // Rounded body of the sheet. Keeps the contour valid while the panel is
    // only a few pixels tall.
    readonly property real panelBodyHeight: Math.max(
        panelShoulderDrop + panelBottomRadius + 16, panelHeight * reveal)
    // The pour grows in once the sheet has dropped, so it never stretches the
    // opening animation into a long tail.
    readonly property real panelMeltHeight: panelMelt * contentReveal
    readonly property real panelShapeHeight: panelBodyHeight + panelMeltHeight

    readonly property string panelFillPath: {
        const h = panelBodyHeight;
        const m = panelMeltHeight;
        const r = panelBottomRadius;
        const sr = panelShoulderRadius;
        const top = Dimensions.frame.thickness;

        if (root.mirror) {
            // Right-aligned mirror: `br` is the body edge at the physical
            // screen edge, `bl` the body edge under the shoulder, and the
            // bottom-right corner bends down into that same edge.
            const br = panelShapeWidth;
            const bl = panelFlare;
            return `M ${br} 0 H ${bl - sr} V ${top}`
                + ` A ${sr} ${sr} 0 0 1 ${bl} ${top + sr} V ${h - r}`
                + ` Q ${bl} ${h} ${bl + r} ${h} H ${br - m}`
                + ` C ${br - m * 0.375} ${h} ${br} ${h} ${br} ${h + m}`
                + ` V 0 Z`;
        }

        // Left-aligned body: `bl` is the body edge at the physical screen
        // edge, `w` the body edge under the shoulder, and the bottom-left
        // corner melts into the frame strip.
        const w = panelShapeWidth - panelFlare;
        const bl = 0;
        return `M ${bl} 0 H ${w + sr} V ${top}`
            + ` A ${sr} ${sr} 0 0 0 ${w} ${top + sr} V ${h - r}`
            + ` Q ${w} ${h} ${w - r} ${h} H ${bl + m}`
            + ` C ${bl + m * 0.375} ${h} ${bl} ${h} ${bl} ${h + m}`
            + ` V 0 Z`;
    }

    // Subclass content. The area already carries the horizontal insets and the
    // content fade/slide, so children anchor to it directly.
    default property alias sheetContent: contentArea.data

    // Emitted once the exit animation finished, after the panel is fully
    // collapsed, so a subclass can reset its page state.
    signal didClose()
    // Emitted when a click outside the panel asks for the sheet to close. The
    // subclass decides what closing means for it.
    signal dismissalRequested()

    function revealOpen() {
        if (root.opened)
            return;

        revealAnim.stop();
        root.opened = true;
        if (root.reveal <= 0.001)
            root.reveal = 0;
        root.forceActiveFocus();
        root.animateReveal(1, Motion.sheetEnter, [0.2, 0, 0, 1]);
    }

    function revealClose() {
        if (!root.opened)
            return;

        revealAnim.stop();
        root.opened = false;

        if (root.reveal <= 0.01) {
            root.reveal = 0;
            root.didClose();
            return;
        }

        root.animateReveal(0, Motion.sheetExit, [0.3, 0, 1, 1]);
    }

    function animateReveal(to, duration, curve) {
        revealAnim.stop();
        revealAnim.to = to;
        revealAnim.duration = duration;
        revealAnim.easing.type = Easing.Bezier;
        revealAnim.easing.bezierCurve = curve;
        revealAnim.start();
    }

    focus: opened

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        duration: Motion.sheetEnter
        easing.type: Easing.Bezier
        easing.bezierCurve: [0.2, 0, 0, 1]

        onFinished: {
            if (root.opened)
                return;

            root.reveal = 0;
            root.didClose();
        }
    }

    // Modal scrim over the desktop below the bar strip. It fades in with the
    // reveal so the sheet reads as a modal surface, while the strip stays
    // crisp and the sheet keeps pouring out of it.
    Rectangle {
        id: scrim

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: parent.height - Dimensions.bar.height
        color: Colors.withAlpha(Colors.scrim, 0.3)
        opacity: root.reveal
        visible: root.modal
        z: 1
    }

    // Full-window dismissal layer. The bar input mask expands to the whole
    // screen while a sheet is open, so this catches any click outside the
    // panel. It sits below the panel itself.
    MouseArea {
        id: dismissArea

        anchors.fill: parent
        enabled: root.modal
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: 0
        onClicked: root.dismissalRequested()
    }

    // Panel viewport. Its height is the revealed part of the panel; the
    // content tree inside keeps its final size, so opening and page sizing
    // never resquash the layout.
    Item {
        id: popout

        x: root.mirror ? root.width - root.panelShapeWidth : 0
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

            // Subclass content. It fades and settles while the sheet reveals;
            // the horizontal insets are already applied, while the top inset
            // stays exposed because the settings pages lay out their own
            // headers through `topInset`.
            Item {
                id: contentArea

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: root.contentLeftInset
                    rightMargin: root.contentRightInset
                }
                z: 1
                opacity: root.contentReveal
                transform: Translate { y: (1.0 - root.contentReveal) * -10 }
            }
        }
    }
}
