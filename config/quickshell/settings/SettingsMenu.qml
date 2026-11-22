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
    // Page sliding in during a navigation transition. Empty while idle, so
    // `page` is then the only visible page.
    property string incomingPage: ""
    property bool opened: false

    // 0 = hidden, 1 = fully visible. Drives the panel clip, the scrim and the
    // content fade/slide. The panel is inside the already-mapped bar surface,
    // so no Wayland resize or first-frame wait is needed.
    property real reveal: 0

    // Shared-axis page transition: 0 = only the outgoing page, 1 = only the
    // incoming one. `pageDirection` is +1 forward (main to subpage) and -1
    // back, so the outgoing page slides out opposite to the incoming one.
    property real pageProgress: 1
    property int pageDirection: 1
    property int revealTick: 0

    // Height of the visible panel itself. The panel background morphs between
    // pages while the pages slide, so no layout animation is visible. The
    // backing surface is the bar window and never resizes.
    property real panelHeight: mainHeight

    // Exposed for the bar input mask. While the menu is open it behaves like a
    // modal popup: the whole screen is captured so an outside click can
    // dismiss it even though the panel itself lives in the bar surface.
    readonly property bool modal: opened || reveal > 0.001

    readonly property int popupWidth: 424
    readonly property int mainHeight: 328
    readonly property int bluetoothHeight: 520
    readonly property int internetHeight: 546

    // Distance a page travels during a navigation transition. Local optical
    // offset, not a shared metric.
    readonly property int pageSlide: 40

    // Height of the page viewport. Both pages keep their intrinsic height
    // during a transition, so the viewport is the taller of the two and
    // neither page is clipped or reflowed while it slides.
    readonly property real targetHeight: root.incomingPage !== ""
        ? Math.max(root.heightForPage(root.page), root.heightForPage(root.incomingPage))
        : root.heightForPage(root.page)

    // The sheet is flush with the physical screen edge (left body edge x = 0),
    // so while the menu is open it covers the decorative frame ring and the
    // compositor's active-window border just like the night-light sheet on the
    // right. It begins exactly at the bar's bottom edge; its opaque fill matches
    // the bar and the frame ring, so the junction is seamless and nothing shows
    // through.
    readonly property int popoutX: 0
    readonly property int popoutY: Dimensions.bar.height

    readonly property int panelBottomRadius: Dimensions.radius.extraLarge
    // The sheet sits on the desktop frame. Its lower left corner pours down
    // that frame: instead of a rounded corner, the bottom edge bends towards
    // the frame and melts into it over this many pixels, so the panel and the
    // frame read as one continuous surface.
    readonly property int panelMelt: Dimensions.radius.extraExtraLarge
    // Distance from the popup width to the sheet's body edge, which is also the
    // page content's right inset. The shoulder is safe to draw over the frame
    // ring only because the sheet, the bar and the frame all use the same opaque
    // fill: a translucent sheet turned the flare into a pale, fringed notch.
    readonly property int panelFlare: 32
    // The shoulder is the same quarter circle as the lower right corner, only
    // concave: it starts at the bottom edge of the frame ring and meets the
    // sheet's right edge one radius lower, so both ends of the sheet round the
    // same way. `panelShoulderDrop` is where the shoulder ends below the sheet's
    // top edge.
    readonly property int panelShoulderRadius: panelBottomRadius
    readonly property int panelShoulderDrop: Dimensions.frame.thickness + panelShoulderRadius
    // Body geometry reaches the physical screen edge; the page viewport keeps
    // one frame thickness of visual padding inside it.
    readonly property int panelBodyLeft: 0
    readonly property int contentTopInset: panelShoulderDrop + 8
    readonly property int contentLeftInset: Dimensions.frame.thickness
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
        panelShoulderDrop + panelBottomRadius + 16,
        panelHeight * reveal)
    // The pour grows in once the sheet has dropped, so it never stretches the
    // opening animation into a long tail.
    readonly property real panelMeltHeight: panelMelt * contentReveal
    readonly property real panelShapeHeight: panelBodyHeight + panelMeltHeight

    // Right shoulder arcs outward into the chrome's bottom edge with the same
    // radius as the lower right corner. The left edge stays on the frame; the
    // bottom edge bends down at the left and flows into that frame strip, so no
    // rounded corner or notch is left where the two meet.
    readonly property string panelFillPath: {
        const w = panelShapeWidth - panelFlare;
        const h = panelBodyHeight;
        const m = panelMeltHeight;
        const r = panelBottomRadius;
        const sr = panelShoulderRadius;
        const top = Dimensions.frame.thickness;
        const bl = panelBodyLeft;
        return `M ${bl} 0 H ${w + sr} V ${top}`
            + ` A ${sr} ${sr} 0 0 0 ${w} ${top + sr} V ${h - r}`
            + ` Q ${w} ${h} ${w - r} ${h} H ${bl + m}`
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

    // Shared-axis geometry for one page. Both pages stay laid out at their
    // final size; only x and opacity animate, so no page layout moves.
    function pageX(name) {
        if (root.incomingPage === "")
            return 0;
        if (name === root.page)
            return -root.pageDirection * root.pageSlide * root.pageProgress;
        if (name === root.incomingPage)
            return root.pageDirection * root.pageSlide * (1.0 - root.pageProgress);
        return 0;
    }

    function pageOpacity(name) {
        if (root.incomingPage === "")
            return name === root.page ? 1.0 : 0.0;
        if (name === root.page)
            return 1.0 - root.pageProgress;
        if (name === root.incomingPage)
            return root.pageProgress;
        return 0.0;
    }

    function pageVisible(name) {
        return name === root.page || name === root.incomingPage;
    }

    function open(page) {
        const target = page ?? "main";

        if (!root.opened) {
            pageProgressAnim.stop();
            panelHeightAnim.stop();
            revealAnim.stop();

            root.page = target;
            root.incomingPage = "";
            root.pageProgress = 1;
            root.panelHeight = root.heightForPage(target);
            root.reveal = 0;
            root.opened = true;
            root.revealTick++;
            root.forceActiveFocus();
            root.animateReveal(1, Motion.sheetEnter, [0.2, 0, 0, 1]);
        } else {
            root.navigate(target);
        }
    }

    function close() {
        if (!root.opened)
            return;

        root.opened = false;
        revealAnim.stop();
        pageProgressAnim.stop();
        panelHeightAnim.stop();

        if (root.reveal <= 0.01) {
            root.reveal = 0;
            root.reset();
            return;
        }

        root.animateReveal(0, Motion.sheetExit, [0.3, 0, 1, 1]);
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open("main");
    }

    // Page-to-page navigation: a shared-axis slide. The outgoing page slides
    // out and fades while the incoming one slides in from the opposite side,
    // and the empty panel background morphs to the new height at the same
    // time. Layout itself never animates.
    function navigate(page) {
        if (!root.opened)
            return;

        if (root.incomingPage !== "") {
            // Already heading to the requested page.
            if (page === root.incomingPage && pageProgressAnim.to === 1)
                return;

            // Already heading back to the anchor page.
            if (page === root.page && pageProgressAnim.to === 0)
                return;

            // The requested page is one of the two in flight: reverse the
            // running transition instead of snapping to a committed state.
            if (page === root.page || page === root.incomingPage) {
                const toAnchor = page === root.page;
                const height = root.heightForPage(page);

                if (Math.abs(root.panelHeight - height) > 0.5) {
                    panelHeightAnim.stop();
                    panelHeightAnim.to = height;
                    panelHeightAnim.duration = Motion.pageBack;
                    panelHeightAnim.start();
                } else {
                    root.panelHeight = height;
                }

                pageProgressAnim.stop();
                pageProgressAnim.to = toAnchor ? 0 : 1;
                pageProgressAnim.duration = toAnchor ? Motion.pageBack : Motion.pageForward;
                pageProgressAnim.start();
                return;
            }

            // A different page was requested: commit the running
            // destination, then start the new transition from there.
            root.page = root.incomingPage;
            root.incomingPage = "";
            root.pageProgress = 1;
        }

        if (root.page === page)
            return;

        const forward = root.page === "main";
        const duration = forward ? Motion.pageForward : Motion.pageBack;

        root.pageDirection = forward ? 1 : -1;
        root.incomingPage = page;
        root.pageProgress = 0;

        const targetHeight = root.heightForPage(page);
        if (Math.abs(root.panelHeight - targetHeight) > 0.5) {
            panelHeightAnim.stop();
            panelHeightAnim.to = targetHeight;
            panelHeightAnim.duration = duration;
            panelHeightAnim.start();
        } else {
            root.panelHeight = targetHeight;
        }

        pageProgressAnim.stop();
        pageProgressAnim.to = 1;
        pageProgressAnim.duration = duration;
        pageProgressAnim.start();
    }

    function animateReveal(to, duration, curve) {
        revealAnim.stop();
        revealAnim.to = to;
        revealAnim.duration = duration;
        revealAnim.easing.type = Easing.Bezier;
        revealAnim.easing.bezierCurve = curve;
        revealAnim.start();
    }

    function reset() {
        revealAnim.stop();
        pageProgressAnim.stop();
        panelHeightAnim.stop();
        root.panelHeight = root.mainHeight;
        root.page = "main";
        root.incomingPage = "";
        root.pageProgress = 1;
        root.reveal = 0;
    }

    Keys.onEscapePressed: function (event) {
        const current = root.incomingPage !== "" ? root.incomingPage : root.page;
        if (current === "bluetooth" || current === "internet")
            root.navigate("main");
        else
            root.close();

        event.accepted = true;
    }

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        duration: Motion.sheetEnter
        easing.type: Easing.Bezier
        easing.bezierCurve: [0.2, 0, 0, 1]

        onFinished: {
            if (!root.opened) {
                root.reveal = 0;
                root.reset();
            }
        }
    }

    // Shared-axis page slide. `panelHeight` morphs alongside it, and the
    // incoming page is committed when the slide finishes.
    NumberAnimation {
        id: pageProgressAnim

        target: root
        property: "pageProgress"
        to: 1
        duration: Motion.pageForward
        easing.type: Easing.Bezier
        easing.bezierCurve: [0.2, 0, 0, 1]

        onFinished: {
            if (root.incomingPage === "")
                return;

            const target = root.incomingPage;
            const reversed = pageProgressAnim.to === 0;
            root.incomingPage = "";
            root.pageProgress = 1;

            // A reversed transition settles back on its anchor page; a
            // forward one commits to the incoming page.
            if (!reversed)
                root.page = target;
        }
    }

    // Only the empty rounded panel is visible while this runs, so this is a
    // cheap geometry animation with no page layout inside it.
    NumberAnimation {
        id: panelHeightAnim

        target: root
        property: "panelHeight"
        duration: Motion.pageForward
        easing.type: Easing.Bezier
        easing.bezierCurve: [0.2, 0, 0, 1]
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

    // Modal scrim over the desktop below the bar strip. It fades in with the
    // reveal so the sheet reads as a modal surface, while the bar strip stays
    // crisp and the sheet keeps pouring out of it. The bar surface is on the
    // Top layer, so this dims windows and the decorative frame too.
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
                    fillColor: Colors.surfaceContainerLow
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

            // Page tree. The wrapper only fades and settles while the sheet
            // itself reveals; page navigation is a shared-axis slide driven by
            // each page's x/opacity bindings.
            Item {
                id: content

                anchors.fill: parent
                z: 1
                opacity: root.contentReveal
                transform: Translate { y: (1.0 - root.contentReveal) * -10 }

                Item {
                    id: pages

                    // Pages are laid out at their final size immediately.
                    // The background panel morphs around them while they
                    // slide, so no page layout is animated.
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        leftMargin: root.contentLeftInset
                        rightMargin: root.contentRightInset
                    }
                    height: root.targetHeight
                    clip: true

                    MainPage {
                        x: root.pageX("main")
                        y: 0
                        width: parent.width
                        height: root.heightForPage("main")
                        topInset: root.contentTopInset
                        revealTick: root.revealTick
                        visible: root.pageVisible("main")
                        opacity: root.pageOpacity("main")
                        onOpen: page => root.navigate(page)
                    }

                    BluetoothPage {
                        x: root.pageX("bluetooth")
                        y: 0
                        width: parent.width
                        height: root.heightForPage("bluetooth")
                        topInset: root.contentTopInset
                        visible: root.pageVisible("bluetooth")
                        opacity: root.pageOpacity("bluetooth")
                        onBack: root.navigate("main")
                    }

                    InternetPage {
                        x: root.pageX("internet")
                        y: 0
                        width: parent.width
                        height: root.heightForPage("internet")
                        topInset: root.contentTopInset
                        visible: root.pageVisible("internet")
                        opacity: root.pageOpacity("internet")
                        onBack: root.navigate("main")
                    }
                }
            }
        }
    }

}
