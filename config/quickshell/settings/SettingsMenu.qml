import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../theme"
import "../bar/components"

// Settings launcher: gear button at the far left of the bar. One popup whose
// content switches between the category grid and individual setting pages,
// like navigating between pages of a website.
Item {
    id: root

    implicitWidth: Dimensions.control.iconButton
    implicitHeight: Dimensions.bar.height

    property string page: "main"
    property string pendingPage: "main"
    property bool opened: false

    // 0 = hidden, 1 = fully visible. Drives opacity + a small slide instead
    // of animating the panel's height/clip: opacity/transform stay cheap and
    // avoid re-laying out the whole page tree on every frame.
    property real reveal: 0

    // Opacity of the page tree. Page switches fade it out, morph the empty
    // panel background to the new size, then fade the new page back in.
    // Page layout itself is never animated.
    property real contentOpacity: 1
    property int revealTick: 0

    // The first frames of a freshly mapped Wayland surface are not presented,
    // so the reveal waits for the popup's first real frame instead of running
    // while the window is still being created.
    property bool pendingReveal: false

    readonly property int popupWidth: 380
    readonly property int mainHeight: 164
    readonly property int bluetoothHeight: 520
    readonly property int internetHeight: 520
    readonly property int soundHeight: 570
    readonly property int maxPanelHeight: Math.max(mainHeight, bluetoothHeight, internetHeight, soundHeight)

    readonly property real targetHeight: heightForPage(page)

    function heightForPage(name) {
        if (name === "bluetooth")
            return bluetoothHeight;
        if (name === "internet")
            return internetHeight;
        if (name === "sound")
            return soundHeight;
        return mainHeight;
    }

    // Height of the visible panel itself. The panel background morphs between
    // pages while the page content is faded out, so no layout animation is
    // visible and no Wayland surface resize happens (the popup window is
    // always allocated at maxPanelHeight).
    property real panelHeight: mainHeight

    // Constant backing-window size. Resizing a Wayland surface during a
    // transition is the main source of stutter, so the popup is mapped once
    // at the tallest page size and the panel inside it changes height.
    readonly property int windowHeight: maxPanelHeight

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
            root.pendingReveal = true;
            popup.visible = true;
            grab.active = true;
            revealFallback.restart();
        } else {
            root.navigate(target);
        }
    }

    function close() {
        if (!root.opened)
            return;

        root.opened = false;
        root.pendingReveal = false;
        revealFallback.stop();
        panelHeightAnim.stop();
        grab.active = false;

        if (root.reveal <= 0.01) {
            root.reveal = 0;
            popup.visible = false;
            return;
        }

        root.animateReveal(0, 160, Easing.InCubic);
    }

    // Called on the popup's first rendered frame, or by the fallback timer if
    // the compositor never reports one.
    function startReveal() {
        if (!root.pendingReveal)
            return;

        root.pendingReveal = false;
        revealFallback.stop();
        root.revealTick++;
        root.animateReveal(1, 220, Easing.OutCubic);
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
        fadeOutAnim.stop();
        fadeInAnim.stop();
        panelHeightAnim.stop();
        root.contentOpacity = 1;
        root.panelHeight = root.mainHeight;
        root.page = "main";
        root.pendingPage = "main";
        root.reveal = 0;
    }

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: if (!root.opened) popup.visible = false
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

    // The backing window only exists once the popup is mapped; attach to it
    // there so the reveal starts exactly on the first presented frame.
    QtObject {
        id: frameProxy

        signal frameSwapped()
    }

    Connections {
        id: frameWatcher

        target: frameProxy

        function onFrameSwapped() {
            root.startReveal();
        }
    }

    Timer {
        id: revealFallback

        // Short safety net: a long fallback makes the popup feel late even
        // when the compositor never emits a frame signal.
        interval: 80
        onTriggered: root.startReveal()
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

        function openSound(): void {
            root.open("sound");
        }

        function close(): void {
            root.close();
        }
    }

    IconButton {
        id: button

        anchors.centerIn: parent
        icon: Icons.settings
        iconSize: Dimensions.icon.large
        iconOffsetX: -0.5
        iconOffsetY: 1
        active: root.opened
        rotation: root.opened ? 90 : 0
        onClicked: root.toggle()

        Behavior on rotation {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: false

        Shortcut {
            sequence: "Escape"
            enabled: root.opened
            onActivated: {
                if (root.page === "bluetooth" || root.page === "internet" || root.page === "sound")
                    root.navigate("main");
                else
                    root.close();
            }
        }

        // Anchor to the full-height settings item, not the icon button: the
        // button is shorter than the bar, so its bottom edge sits inside the
        // bar and would make the popup overlap the bar's last pixels.
        anchor.item: root
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.Slide

        implicitWidth: root.popupWidth
        implicitHeight: root.windowHeight

        onVisibleChanged: if (!visible) root.reset()

        onBackingWindowVisibleChanged: {
            frameWatcher.target = backingWindowVisible
                ? popup._backingWindow
                : frameProxy;
        }

        // Panel viewport. During page navigation only the empty panel
        // background morphs inside it; the page tree is laid out at its final
        // size and stays hidden until the morph finishes.
        Item {
            id: viewport

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: root.panelHeight

            Item {
                id: panel

                anchors.top: parent.top
                width: parent.width
                height: root.panelHeight
                opacity: root.reveal
                transform: Translate { y: -(1.0 - root.reveal) * 8 }

                Surface {
                    anchors.fill: parent
                    radius: Dimensions.radius.extraLarge
                    surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
                    // Match Hyprland's focused window border: 2px in the
                    // active border color.
                    borderWidth: 2
                    borderColor: Colors.primary
                }

                // Page tree fades away during navigation while the panel
                // background stays visible and morphs to the new size.
                Item {
                    id: content

                    anchors.fill: parent
                    opacity: root.contentOpacity

                    Item {
                        id: pages

                        // Pages are laid out at their final size immediately.
                        // The background panel morphs around them while the
                        // content is hidden, so no page layout is animated.
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: root.targetHeight

                        MainPage {
                            anchors.fill: parent
                            revealTick: root.revealTick
                            visible: root.page === "main"
                            onOpen: page => root.navigate(page)
                        }

                        BluetoothPage {
                            anchors.fill: parent
                            visible: root.page === "bluetooth"
                            onBack: root.navigate("main")
                            onClose: root.close()
                        }

                        InternetPage {
                            anchors.fill: parent
                            visible: root.page === "internet"
                            onBack: root.navigate("main")
                            onClose: root.close()
                        }

                        SoundPage {
                            anchors.fill: parent
                            visible: root.page === "sound"
                            onBack: root.navigate("main")
                            onClose: root.close()
                        }
                    }
                }
            }
        }

        // The backing window is always maxPanelHeight. Clicks in the empty
        // area below a shorter panel behave like clicks outside the popup.
        MouseArea {
            anchors {
                top: viewport.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            onClicked: root.close()
        }
    }

    HyprlandFocusGrab {
        id: grab

        windows: [button.window, popup]
        onCleared: root.close()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.opened
        onActivated: {
            if (root.page === "bluetooth" || root.page === "internet" || root.page === "sound")
                root.navigate("main");
            else
                root.close();
        }
    }

    // Main settings grid. Entries are data-driven so future categories only
    // need an object here plus their own page component.
    component MainPage: Item {
        id: mainPage

        signal open(string page)

        property int revealTick: 0

        implicitWidth: 380
        implicitHeight: 164

        readonly property var entries: [
            {
                icon: Icons.bluetooth,
                title: "Bluetooth",
                subtitle: "Devices & pairing",
                soon: false,
                page: "bluetooth",
            },
            {
                icon: Icons.wifi,
                title: "Internet",
                subtitle: "Networks & Ethernet",
                soon: false,
                page: "internet",
            },
            {
                icon: Icons.volumeUp,
                title: "Sound",
                subtitle: "Output & input",
                soon: false,
                page: "sound",
            },
        ]

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Text {
                text: "Settings"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.bold
            }

            Row {
                spacing: 12

                Repeater {
                    model: mainPage.entries

                    delegate: Item {
                        id: tile

                        required property var modelData
                        required property int index

                        readonly property bool soon: modelData.soon
                        readonly property bool hovered: tileMouse.containsMouse && !tile.soon

                        property real appear: 0

                        width: 108
                        height: 96

                        opacity: tile.appear * (tile.soon ? 0.7 : 1.0)
                        scale: tileMouse.pressed && !tile.soon
                            ? 0.96
                            : tile.hovered ? 1.03 : 1.0

                        transform: Translate { y: (1.0 - tile.appear) * 10 }

                        Behavior on scale {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }

                        SequentialAnimation {
                            id: enterAnim

                            PauseAnimation { duration: 20 + tile.index * 25 }
                            NumberAnimation {
                                target: tile
                                property: "appear"
                                to: 1
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        Connections {
                            target: mainPage

                            function onRevealTickChanged() {
                                tile.appear = 0;
                                enterAnim.restart();
                            }
                        }

                        Component.onCompleted: {
                            if (mainPage.revealTick > 0)
                                enterAnim.start();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Dimensions.radius.medium
                            color: tile.soon
                                ? Colors.surfaceContainerHigh
                                : tile.hovered
                                    ? Colors.stateLayer(Colors.primary, 0.16)
                                    : Colors.withAlpha(Colors.primary, 0.07)
                            border.width: 1
                            border.color: tile.soon
                                ? Colors.withAlpha(Colors.outlineVariant, 0.4)
                                : Colors.withAlpha(Colors.primary, tile.hovered ? 0.7 : 0.28)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: tileIcon

                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.icon
                                color: tile.soon
                                    ? Colors.withAlpha(Colors.onSurfaceVariant, 0.6)
                                    : Colors.primary
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.extraLarge
                                scale: tile.hovered ? 1.14 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.title
                                color: tile.soon
                                    ? Colors.withAlpha(Colors.onSurface, 0.7)
                                    : Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: Typography.weight.medium
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.subtitle
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                            }
                        }

                        MouseArea {
                            id: tileMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !tile.soon
                            cursorShape: tile.soon ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (tile.modelData.page)
                                    mainPage.open(tile.modelData.page);
                            }
                        }
                    }
                }
            }
        }
    }
}
