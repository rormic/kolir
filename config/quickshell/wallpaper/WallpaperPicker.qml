pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../services"
import "../theme"

// Wallpaper picker overlay. Replaces the Zenity file dialog for SUPER+CTRL+T:
// a grid of cached 16:9 thumbnails from ~/Pictures/wallpaper, keyboard and
// mouse selection, a Random action, and Escape/outside-click dismissal that
// applies nothing (the same contract as cancelling the Zenity picker).
//
// Thumbnails are produced by scripts/wallpaper-thumbnails.sh into the
// Quickshell cache: the picker never decodes a full-size wallpaper, existing
// previews appear immediately and the rest stream in while the worker runs.
// A selection still goes through the unchanged set-wallpaper.sh and
// generate-colors.sh helpers.
Scope {
    id: root

    // ── Panel geometry ───────────────────────────────────────────────────
    readonly property int panelWidth: 1180
    readonly property int panelHeight: 800
    readonly property int screenMargin: 48
    readonly property int headerHeight: 56
    readonly property int footerHeight: 44
    readonly property int contentPadding: 16
    readonly property int tileSpacing: 12
    readonly property int gridColumns: 5
    // Mirror WallpaperTile.qml's chrome so a grid cell reserves exactly the
    // space the tile needs for its thumbnail, inset and file-name label.
    readonly property int tileInset: 6
    readonly property int tileLabelHeight: 28
    readonly property real thumbnailAspect: 16 / 9
    readonly property int focusDelay: 20
    // Extra rows kept alive above/below the viewport so a fling does not have
    // to build and decode a delegate on the frame it appears.
    readonly property int prefetchRows: 2

    // GridView positions cells on a fixed pitch, so the pitch has to fit the
    // content width exactly; the visible tile is one spacing narrower.
    readonly property real cellWidth: Math.floor(
        (panel.width - root.contentPadding * 2) / root.gridColumns)
    readonly property real tileWidth: root.cellWidth - root.tileSpacing
    readonly property real tileImageHeight: Math.round(root.tileWidth / root.thumbnailAspect)
    readonly property real tileHeight: root.tileImageHeight
        + root.tileLabelHeight + root.tileInset * 2 + root.tileInset / 2

    // 0 = hidden, 1 = fully visible. The window stays mapped at full screen,
    // only the panel fades/slides so Wayland never sees a resize.
    property real reveal: 0
    property bool scanning: false
    property int total: 0
    property string scanError: ""

    function consumeLine(line) {
        const parts = line.split("\t");

        if (parts[0] === "total") {
            root.total = Number(parts[1]) || 0;
            return;
        }
        if (parts.length < 2 || parts[0] === "")
            return;

        const path = parts[0];
        wallpaperModel.append({
            path: path,
            thumb: parts[1] || "",
            name: path.substring(path.lastIndexOf("/") + 1),
        });

        if (wallpaperModel.count === 1)
            grid.currentIndex = 0;
    }

    function startScan() {
        if (scanProc.running)
            return;

        wallpaperModel.clear();
        grid.currentIndex = -1;
        root.total = 0;
        root.scanError = "";
        root.scanning = true;
        scanProc.running = true;
    }

    function open() {
        root.startScan();

        if (!win.visible) {
            root.reveal = 0;
            win.visible = true;
        }
        revealOut.stop();
        revealIn.restart();
        focusTimer.restart();
    }

    function close() {
        if (!win.visible)
            return;

        revealIn.stop();
        revealOut.restart();
    }

    function toggle() {
        if (win.visible)
            root.close();
        else
            root.open();
    }

    function applyCurrent() {
        if (grid.currentIndex < 0 || grid.currentIndex >= wallpaperModel.count)
            return;

        root.applyWallpaper(wallpaperModel.get(grid.currentIndex).path);
    }

    function clampScroll(y) {
        const max = Math.max(0, grid.contentHeight - grid.height);
        return Math.max(0, Math.min(max, y));
    }

    // The helper chain is the same one select-wallpaper.sh uses after Zenity
    // returns: apply the image, then regenerate the palette.
    function applyWallpaper(path) {
        if (path === "")
            return;

        root.close();
        applyProc.command = [
            "sh", "-c", 'sh "$1" "$3" && sh "$2"',
            "kolir-wallpaper",
            ShellPaths.hyprScripts + "/set-wallpaper.sh",
            ShellPaths.hyprScripts + "/generate-colors.sh",
            path,
        ];
        applyProc.running = true;
    }

    // Mirrors random-wallpaper.sh: pick from the same set, apply, regenerate.
    function applyRandom() {
        root.close();
        randomProc.command = ["sh", ShellPaths.hyprScripts + "/random-wallpaper.sh"];
        randomProc.running = true;
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function random(): void {
            root.applyRandom();
        }
    }

    ListModel {
        id: wallpaperModel
    }

    Process {
        id: scanProc

        running: false
        command: [
            "sh",
            ShellPaths.wallpaperThumbnails,
            ShellPaths.wallpaperDir,
            ShellPaths.wallpaperPreviewDir,
        ]

        stdout: SplitParser {
            onRead: line => root.consumeLine(line)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Wallpaper: thumbnail worker:", message);
            }
        }

        onExited: code => {
            root.scanning = false;
        }
    }

    Process {
        id: applyProc

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Wallpaper:", message);
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("Wallpaper: applying the selection failed, exit code", code);
        }
    }

    Process {
        id: randomProc

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Wallpaper:", message);
            }
        }

        onExited: code => {
            if (code !== 0)
                console.warn("Wallpaper: random pick failed, exit code", code);
        }
    }

    NumberAnimation {
        id: revealIn

        target: root
        property: "reveal"
        to: 1
        duration: Motion.popupEnter
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: revealOut

        target: root
        property: "reveal"
        to: 0
        duration: Motion.popupExit
        easing.type: Easing.InCubic

        onFinished: {
            if (root.reveal <= 0.01) {
                root.reveal = 0;
                win.visible = false;
            }
        }
    }

    Timer {
        id: focusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: grid.forceActiveFocus()
    }

    PanelWindow {
        id: win

        visible: false
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        implicitWidth: screen ? screen.width : 0
        implicitHeight: screen ? screen.height : 0

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "wallpaper"
        WlrLayershell.exclusiveZone: 0

        onVisibleChanged: {
            if (!visible) {
                revealIn.stop();
                revealOut.stop();
                root.reveal = 0;
            }
        }

        // Clicking anywhere outside the panel dismisses it without applying.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            anchors.fill: parent
            opacity: root.reveal
            transform: Translate { y: -(1.0 - root.reveal) * 8 }

            // Dimmed backdrop: keeps the grid readable over any wallpaper.
            Rectangle {
                anchors.fill: parent
                color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.45)
            }

            Surface {
                id: panel

                anchors.centerIn: parent
                width: Math.min(root.panelWidth, win.width - root.screenMargin * 2)
                height: Math.min(root.panelHeight, win.height - root.screenMargin * 2)
                radius: Dimensions.radius.extraLarge
                surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
                borderWidth: 2
                borderColor: Colors.primary

                // Clicks inside the panel must not reach the dismissal layer.
                MouseArea {
                    anchors.fill: parent
                }

                Item {
                    id: headerBar

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: root.headerHeight

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        text: Icons.wallpaper
                        color: Colors.primary
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.extraLarge
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 52
                            verticalCenter: parent.verticalCenter
                        }
                        text: "Wallpaper"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.titleSmall
                        font.weight: Typography.weight.bold
                    }

                    Row {
                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Pill {
                            id: randomPill

                            icon: Icons.shuffle
                            text: "Random"
                            horizontalPadding: 12

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyRandom()
                            }
                        }

                        IconButton {
                            icon: Icons.close
                            iconSize: Dimensions.icon.medium
                            onClicked: root.close()
                        }
                    }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                    }
                }

                GridView {
                    id: grid

                    anchors {
                        top: headerBar.bottom
                        bottom: footerBar.top
                        left: parent.left
                        right: parent.right
                        margins: root.contentPadding
                    }

                    clip: true
                    focus: true
                    model: wallpaperModel
                    currentIndex: -1
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: root.cellHeight * root.prefetchRows

                    cellWidth: root.cellWidth
                    cellHeight: root.tileHeight + root.tileSpacing

                    // Flickable's default wheel step is a few dozen pixels,
                    // which feels stuck in a grid of ~170px cells. Mouse wheel
                    // moves a whole row per notch; touchpad pixel deltas stay
                    // 1:1 for a native feel.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            const pixel = event.pixelDelta.y;
                            const angle = event.angleDelta.y;

                            grid.cancelFlick();
                            if (pixel !== 0)
                                grid.contentY = root.clampScroll(grid.contentY - pixel);
                            else if (angle !== 0)
                                grid.contentY = root.clampScroll(
                                    grid.contentY - Math.sign(angle) * grid.cellHeight);
                            event.accepted = true;
                        }
                    }

                    Keys.onReturnPressed: root.applyCurrent()
                    Keys.onEnterPressed: root.applyCurrent()
                    Keys.onEscapePressed: root.close()

                    delegate: WallpaperTile {
                        required property int index
                        required property string path
                        required property string thumb
                        required property string name

                        width: grid.cellWidth - root.tileSpacing
                        height: grid.cellHeight - root.tileSpacing
                        thumbnailSource: thumb
                        fileName: name
                        selected: GridView.isCurrentItem

                        onActivated: root.applyWallpaper(path)
                    }
                }

                Column {
                    anchors.centerIn: grid
                    spacing: 10
                    visible: wallpaperModel.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.scanning ? Icons.wallpaper : Icons.searchOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: 32
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.scanning
                            ? "Preparing previews…"
                            : "No wallpapers in " + ShellPaths.wallpaperDir
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }

                Item {
                    id: footerBar

                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.footerHeight

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        text: "[Arrows] Select   [Enter] Apply   [Esc] Close"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                    }

                    Row {
                        anchors {
                            right: parent.right
                            rightMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        ProgressIndicator {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120
                            visible: root.scanning
                            value: root.total > 0
                                ? wallpaperModel.count / root.total * 100
                                : 0
                            animated: false
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.scanning
                                ? "Previews " + wallpaperModel.count
                                    + (root.total > 0 ? " / " + root.total : "")
                                : wallpaperModel.count
                                    + (wallpaperModel.count === 1 ? " wallpaper" : " wallpapers")
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }
                    }
                }
            }
        }
    }
}
