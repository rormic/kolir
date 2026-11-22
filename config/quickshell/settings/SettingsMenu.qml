import QtQuick
import Quickshell.Io
import "../bar/components"
import "../theme"

// Settings launcher and popout. The surface, scrim, reveal and dismissal come
// from EmbeddedSheet, so it grows out of the bar the same way the night-light
// and sound sheets do. This file owns the page state and the shared-axis page
// slide; the panel background morphs between pages while the pages slide, so
// no layout is ever animated.
EmbeddedSheet {
    id: root

    // Page being shown, and the page sliding in during a navigation
    // transition. `incomingPage` is empty while idle, so `page` is then the
    // only visible page.
    property string page: "main"
    property string incomingPage: ""

    // Shared-axis page transition: 0 = only the outgoing page, 1 = only the
    // incoming one. `pageDirection` is +1 forward (main to subpage) and -1
    // back, so the outgoing page slides out opposite to the incoming one.
    property real pageProgress: 1
    property int pageDirection: 1
    property int revealTick: 0

    // Height of the visible panel, morphed between pages while they slide.
    panelHeight: mainHeight

    readonly property int mainHeight: 328
    readonly property int bluetoothHeight: 520
    // Tall enough for the Internet page's resting content, so it does not open
    // with a sliver of scroll (mirrors InternetPage.implicitHeight).
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

            root.page = target;
            root.incomingPage = "";
            root.pageProgress = 1;
            root.panelHeight = root.heightForPage(target);
            root.revealTick++;
            root.revealOpen();
        } else {
            root.navigate(target);
        }
    }

    function close() {
        if (!root.opened)
            return;

        pageProgressAnim.stop();
        panelHeightAnim.stop();
        root.revealClose();
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

    function reset() {
        pageProgressAnim.stop();
        panelHeightAnim.stop();
        root.panelHeight = root.mainHeight;
        root.page = "main";
        root.incomingPage = "";
        root.pageProgress = 1;
    }

    onDismissalRequested: root.close()

    onDidClose: root.reset()

    Keys.onEscapePressed: function (event) {
        const current = root.incomingPage !== "" ? root.incomingPage : root.page;
        if (current === "bluetooth" || current === "internet")
            root.navigate("main");
        else
            root.close();

        event.accepted = true;
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

    Item {
        id: pages

        // Pages are laid out at their final size immediately. The background
        // panel morphs around them while they slide, so no page layout is
        // animated.
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
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
