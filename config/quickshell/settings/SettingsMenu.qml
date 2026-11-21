import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import "../theme"

// Settings launcher and popout. Unlike a floating popup window, the panel is
// drawn inside the bar's own layer surface, directly below the trigger. Its top
// edge is fused with the bar bottom and small concave fillets connect the sides
// back into the bar, so the menu looks like it pours out of the bar.
//
// The root fills the bar window. The trigger sits in the bar strip; the panel
// hangs below it and is clipped while it reveals. Bar.qml makes the window
// modal while the menu is open so outside clicks can dismiss it.
Item {
    id: root

    property string page: "main"
    property string pendingPage: "main"
    property bool opened: false

    // 0 = hidden, 1 = fully visible. Drives the panel clip and the content
    // fade/slide. The panel is inside the already-mapped bar surface, so no
    // Wayland resize or first-frame wait is needed.
    property real reveal: 0

    // Opacity of the page tree. Page switches fade it out, morph the empty
    // panel background to the new size, then fade the new page back in.
    // Page layout itself is never animated.
    property real contentOpacity: 1
    property int revealTick: 0

    // Height of the visible panel itself. The panel background morphs between
    // pages while the page content is faded out, so no layout animation is
    // visible. The backing surface is the bar window and never resizes.
    property real panelHeight: mainHeight

    // Exposed for the bar input mask. While the menu is open it behaves like a
    // modal popup: the whole screen is captured so an outside click can
    // dismiss it even though the panel itself lives in the bar surface.
    readonly property bool modal: opened || reveal > 0.001

    readonly property int popupWidth: 424
    readonly property int mainHeight: 222
    readonly property int bluetoothHeight: 520
    readonly property int internetHeight: 520

    readonly property real targetHeight: heightForPage(page)

    // The popup starts at the screen edge so the left body edge can stay at
    // frame thickness while an outward foot is drawn into the frame.
    readonly property int popoutX: 0
    readonly property int popoutY: Dimensions.bar.height - 1

    readonly property int panelBottomRadius: Dimensions.radius.extraLarge
    // The sheet sits on the desktop frame. Its lower left corner pours down
    // that frame: instead of a rounded corner, the bottom edge bends towards
    // the frame and melts into it over this many pixels, so the panel and the
    // frame read as one continuous surface.
    readonly property int panelMelt: Dimensions.radius.extraExtraLarge
    // Right shoulder at the top, plus the left body edge that stays flush with
    // the desktop frame.
    readonly property int panelFlare: 32
    readonly property int panelShoulderHeight: 32
    readonly property int panelBodyLeft: Dimensions.frame.thickness
    readonly property int contentTopInset: panelShoulderHeight + 8
    readonly property int contentLeftInset: panelBodyLeft
    readonly property int contentRightInset: panelFlare

    // The sheet grows out of the trigger: width first, then height, so it does
    // not appear as a full-width blind dropping from the bar.
    readonly property real revealWidth: Math.min(1, reveal * 1.35)
    readonly property real panelShapeWidth: Math.max(2 * panelFlare + 80,
        popupWidth * revealWidth)
    readonly property real contentReveal: Math.max(0, Math.min(1, (reveal - 0.65) / 0.35))
    // Rounded body of the sheet. Keep the contour valid while the panel is
    // only a few pixels tall.
    readonly property real panelBodyHeight: Math.max(
        panelShoulderHeight + panelBottomRadius + 16,
        panelHeight * reveal)
    // The pour grows in once the sheet has dropped, so it never stretches the
    // opening animation into a long tail.
    readonly property real panelMeltHeight: panelMelt * contentReveal
    readonly property real panelShapeHeight: panelBodyHeight + panelMeltHeight

    // Right shoulder curves outward into the bar. The left edge stays on the
    // frame; the bottom edge bends down at the left and flows into that frame
    // strip, so no rounded corner or notch is left where the two meet.
    readonly property string panelFillPath: {
        const w = panelShapeWidth;
        const h = panelBodyHeight;
        const m = panelMeltHeight;
        const r = panelBottomRadius;
        const f = panelFlare;
        const sh = panelShoulderHeight;
        const bl = panelBodyLeft;
        return `M ${bl} 0 H ${w} Q ${w - f} 0 ${w - f} ${sh} V ${h - r}`
            + ` Q ${w - f} ${h} ${w - f - r} ${h} H ${bl + m}`
            + ` C ${bl + m * 0.375} ${h} ${bl} ${h} ${bl} ${h + m}`
            + ` V 0 Z`;
    }

    focus: opened

    function heightForPage(name) {
        if (name === "bluetooth")
            return bluetoothHeight;
        if (name === "internet")
            return internetHeight;
        return mainHeight;
    }

    function open(page) {
        const target = page ?? "main";

        if (!root.opened) {
            fadeOutAnim.stop();
            fadeInAnim.stop();
            panelHeightAnim.stop();
            revealAnim.stop();

            root.contentOpacity = 1;
            root.pendingPage = target;
            root.page = target;
            root.panelHeight = root.heightForPage(target);
            root.reveal = 0;
            root.opened = true;
            root.revealTick++;
            root.forceActiveFocus();
            root.animateReveal(1, 240, Easing.OutQuint);
        } else {
            root.navigate(target);
        }
    }

    function close() {
        if (!root.opened)
            return;

        root.opened = false;
        revealAnim.stop();
        fadeOutAnim.stop();
        fadeInAnim.stop();
        panelHeightAnim.stop();

        if (root.reveal <= 0.01) {
            root.reveal = 0;
            root.reset();
            return;
        }

        root.animateReveal(0, 160, Easing.InCubic);
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open("main");
    }

    // Page-to-page navigation: fade the old content out, morph the empty
    // panel background to the new size, then fade the new page in.
    function navigate(page) {
        if (!root.opened)
            return;

        if (root.page === page) {
            if (root.pendingPage === page)
                return;

            // A transition away from this page is still running; cancel it
            // and fade the current page back in.
            root.pendingPage = page;
            fadeOutAnim.stop();
            panelHeightAnim.stop();
            fadeInAnim.restart();
            return;
        }

        if (root.pendingPage === page)
            return;

        root.pendingPage = page;
        fadeInAnim.stop();
        panelHeightAnim.stop();
        fadeOutAnim.restart();
    }

    function animateReveal(to, duration, easing) {
        revealAnim.stop();
        revealAnim.to = to;
        revealAnim.duration = duration;
        revealAnim.easing.type = easing;
        revealAnim.start();
    }

    function reset() {
        revealAnim.stop();
        fadeOutAnim.stop();
        fadeInAnim.stop();
        panelHeightAnim.stop();
        root.contentOpacity = 1;
        root.panelHeight = root.mainHeight;
        root.page = "main";
        root.pendingPage = "main";
        root.reveal = 0;
    }

    Keys.onEscapePressed: function (event) {
        if (root.page === "bluetooth" || root.page === "internet")
            root.navigate("main");
        else
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
            if (!root.opened) {
                root.reveal = 0;
                root.reset();
            }
        }
    }

    // Fade-through: old page out, morph the empty panel background to the
    // new size, then fade the new page in. Pagination itself never animates
    // layout because the content is invisible while `page` changes.
    NumberAnimation {
        id: fadeOutAnim

        target: root
        property: "contentOpacity"
        to: 0
        duration: 80
        easing.type: Easing.OutCubic

        onFinished: {
            if (!root.opened || root.page === root.pendingPage)
                return;

            root.page = root.pendingPage;

            const target = root.heightForPage(root.page);
            if (Math.abs(root.panelHeight - target) < 0.5) {
                root.panelHeight = target;
                fadeInAnim.restart();
                return;
            }

            panelHeightAnim.stop();
            panelHeightAnim.to = target;
            panelHeightAnim.start();
        }
    }

    NumberAnimation {
        id: fadeInAnim

        target: root
        property: "contentOpacity"
        to: 1
        duration: 140
        easing.type: Easing.OutCubic
    }

    // Only the empty rounded panel is visible while this runs, so this is a
    // cheap geometry animation with no page layout inside it.
    NumberAnimation {
        id: panelHeightAnim

        target: root
        property: "panelHeight"
        duration: 200
        easing.type: Easing.OutCubic

        onFinished: {
            if (root.opened && root.page === root.pendingPage)
                fadeInAnim.restart();
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open("main");
        }

        function openBluetooth(): void {
            root.open("bluetooth");
        }

        function openInternet(): void {
            root.open("internet");
        }

        function close(): void {
            root.close();
        }
    }

    // Full-window dismissal layer. The bar input mask expands to the whole
    // screen while the menu is open, so this catches any click outside the
    // panel. It sits below the bar content and the panel itself.
    MouseArea {
        id: dismissArea

        anchors.fill: parent
        enabled: root.modal
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: 0
        onClicked: root.close()
    }

    // Panel viewport. Its height is the revealed part of the panel; the page
    // tree inside keeps its final size, so opening and page sizing never
    // resquash the layout.
    Item {
        id: popout

        x: root.popoutX
        y: root.popoutY
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
                    fillColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.94)
                    strokeWidth: 0

                    PathSvg {
                        path: root.panelFillPath
                    }
                }
            }

            // Swallow clicks on empty panel areas so they do not fall through
            // to the full-window dismissal layer and close the menu.
            MouseArea {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: root.panelShoulderHeight
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

            // Page tree fades away during navigation while the panel
            // background stays visible and morphs to the new size.
            Item {
                id: content

                anchors.fill: parent
                z: 1
                opacity: root.contentOpacity * root.contentReveal
                transform: Translate { y: (1.0 - root.contentReveal) * -10 }

                Item {
                    id: pages

                    // Pages are laid out at their final size immediately.
                    // The background panel morphs around them while the
                    // content is hidden, so no page layout is animated.
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        leftMargin: root.contentLeftInset
                        rightMargin: root.contentRightInset
                    }
                    height: root.targetHeight

                    MainPage {
                        anchors.fill: parent
                        topInset: root.contentTopInset
                        revealTick: root.revealTick
                        visible: root.page === "main"
                        onOpen: page => root.navigate(page)
                    }

                    BluetoothPage {
                        anchors.fill: parent
                        topInset: root.contentTopInset
                        visible: root.page === "bluetooth"
                        onBack: root.navigate("main")
                    }

                    InternetPage {
                        anchors.fill: parent
                        topInset: root.contentTopInset
                        visible: root.page === "internet"
                        onBack: root.navigate("main")
                    }
                }
            }
        }
    }

}
