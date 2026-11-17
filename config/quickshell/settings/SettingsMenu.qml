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

    // 0 = tucked into the bar, 1 = fully revealed. The panel unrolls downward
    // instead of appearing instantly.
    property real reveal: 0
    property int revealTick: 0

    // The first frames of a freshly mapped Wayland surface are not presented,
    // so the reveal waits for the popup's first real frame instead of running
    // while the window is still being created.
    property bool pendingReveal: false

    readonly property int popupWidth: 380
    readonly property int mainHeight: 164
    readonly property int bluetoothHeight: 520
    readonly property int internetHeight: 520

    readonly property real targetHeight: {
        if (page === "bluetooth")
            return bluetoothHeight;
        if (page === "internet")
            return internetHeight;
        return mainHeight;
    }

    // Height of the visible panel itself, independent of the reveal wipe.
    // Animated when moving between pages so the popup grows/shrinks smoothly.
    property real panelHeight: mainHeight

    // Keep the window large enough while the panel animates.
    readonly property int windowHeight: Math.ceil(Math.max(panelHeight, targetHeight))

    function open(page) {
        const target = page ?? "main";

        if (!root.opened) {
            fadeOutAnim.stop();
            fadeInAnim.stop();
            panelHeightAnim.stop();
            pages.opacity = 1;
            root.pendingPage = target;
            root.page = target;
            root.panelHeight = root.targetHeight;
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
        grab.active = false;
        root.animateReveal(0, 190, Easing.InCubic);
    }

    // Called on the popup's first rendered frame, or by the fallback timer if
    // the compositor never reports one.
    function startReveal() {
        if (!root.pendingReveal)
            return;

        root.pendingReveal = false;
        revealFallback.stop();
        root.revealTick++;
        root.animateReveal(1, 280, Easing.OutCubic);
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open("main");
    }

    // Page-to-page navigation, like changing pages on a website: the current
    // page fades away, then the new one fades in while the panel resizes.
    function navigate(page) {
        if (root.page === page || root.pendingPage === page)
            return;

        root.pendingPage = page;
        fadeInAnim.stop();
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
        pages.opacity = 1;
        root.panelHeight = root.mainHeight;
        root.page = "main";
        root.pendingPage = "main";
        root.reveal = 0;
    }

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        duration: 260
        easing.type: Easing.OutCubic
        onFinished: if (!root.opened) popup.visible = false
    }

    // Fade-through: old page out, swap, new page in, panel resizes alongside.
    NumberAnimation {
        id: fadeOutAnim

        target: pages
        property: "opacity"
        to: 0
        duration: 70
        easing.type: Easing.InCubic

        onFinished: {
            if (!root.opened || root.page === root.pendingPage)
                return;

            root.page = root.pendingPage;
            panelHeightAnim.stop();
            panelHeightAnim.to = root.targetHeight;
            panelHeightAnim.start();
            fadeInAnim.restart();
        }
    }

    NumberAnimation {
        id: fadeInAnim

        target: pages
        property: "opacity"
        to: 1
        duration: 140
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: panelHeightAnim

        target: root
        property: "panelHeight"
        duration: 200
        easing.type: Easing.OutCubic
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

        interval: 300
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
                if (root.page === "bluetooth" || root.page === "internet")
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

        // Viewport that unrolls from under the bar. The panel keeps its full
        // size inside and is simply clipped by the viewport while revealing.
        Item {
            id: viewport

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: root.panelHeight * root.reveal
            clip: true

            Item {
                id: panel

                anchors.top: parent.top
                width: parent.width
                height: root.panelHeight

                Surface {
                    anchors.fill: parent
                    radius: Dimensions.radius.extraLarge
                    surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
                    // Match Hyprland's focused window border: 2px in the
                    // active border color.
                    borderWidth: 2
                    borderColor: Colors.primary
                }

                Item {
                    id: pages

                    anchors.fill: parent

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
                }
            }
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
            if (root.page === "bluetooth" || root.page === "internet")
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
                subtitle: "Soon",
                soon: true,
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

                            PauseAnimation { duration: 40 + tile.index * 40 }
                            NumberAnimation {
                                target: tile
                                property: "appear"
                                to: 1
                                duration: 240
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
