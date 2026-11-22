pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../services"
import "../theme"

// Wallpaper picker overlay. Replaces the Zenity file dialog for SUPER+CTRL+T:
// a grid of cached 16:9 thumbnails, keyboard and mouse selection, folder
// navigation, a Random action, and Escape/outside-click dismissal that
// applies nothing (the same contract as cancelling the Zenity picker).
//
// The grid starts in ShellPaths.wallpaperDir and can walk into subfolders
// (shown as folder tiles), back to the parent with Backspace/the up button, or
// straight to the default library with the home button. Navigation lasts for
// the lifetime of the shell.
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
    readonly property int completionDelay: 140
    readonly property int completionRowHeight: 28
    readonly property int maxCompletionRows: 8
    // One extra row above/below the viewport smooths a fling without decoding
    // several offscreen rows up front.
    readonly property int prefetchRows: 1
    // Fraction of a grid row per 120 wheel units. A whole row per notch felt
    // too fast; 0.7 keeps each notch deliberate while high-resolution wheels
    // still accumulate smoothly.
    readonly property real wheelRowsPerNotch: 0.7

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
    property int fileCount: 0
    property string scanError: ""

    // Folder being browsed. Initialised to the shared wallpaper library and
    // kept across open/close for the lifetime of this shell.
    property string currentDir: ShellPaths.wallpaperDir
    readonly property string parentDir: {
        const dir = root.currentDir;

        if (dir === "" || dir === "/")
            return "";

        const slash = dir.lastIndexOf("/");
        return slash <= 0 ? "/" : dir.substring(0, slash);
    }

    // Index of the first wallpaper tile. Directories are listed first, but
    // opening the panel should start on a wallpaper when the folder has one.
    property int firstFileIndex: -1
    // Index of the tile currently under the pointer, kept even while the
    // grid moves so the selection can follow as soon as scrolling stops.
    property int hoveredIndex: -1

    function followHover(index) {
        if (index < 0 || index >= wallpaperModel.count)
            return;
        grid.currentIndex = index;
    }

    // Manual path entry. The draft supports "~", absolute paths and paths
    // relative to the folder being browsed; the validator resolves ".." and
    // symlinks and only accepts readable directories.
    property bool editingPath: false
    property bool pathBusy: false
    property string pathError: ""
    // Directory suggestions for the typed path. Index -1 means no row is
    // highlighted; Enter then validates the text as typed.
    property var completions: []
    property int completionIndex: -1

    function normalizePath(raw) {
        let path = raw.trim();

        if (path === "")
            return "";

        if (path === "~")
            path = ShellPaths.home;
        else if (path.startsWith("~/"))
            path = ShellPaths.home + path.substring(1);
        else if (!path.startsWith("/"))
            path = root.currentDir + "/" + path;

        if (path.length > 1)
            path = path.replace(/\/+$/, "");

        return path;
    }

    function beginPathEdit() {
        root.pathError = "";
        root.clearCompletions();
        root.editingPath = true;
        pathInput.text = root.currentDir;
        pathInput.forceActiveFocus();
        pathInput.selectAll();
        pathFocusTimer.restart();
        completionTimer.restart();
    }

    function cancelPathEdit() {
        completionTimer.stop();
        root.clearCompletions();
        root.editingPath = false;
        root.pathError = "";
        focusTimer.restart();
    }

    function submitPath() {
        if (root.pathBusy)
            return;

        const target = root.normalizePath(pathInput.text);
        if (target === "") {
            root.pathError = "Enter a folder path";
            return;
        }

        root.pathBusy = true;
        root.pathError = "";
        pathCheckProc.resolved = "";
        pathCheckProc.command = [
            "sh", "-c",
            'p=$(readlink -f -- "$1") || exit 1; [ -d "$p" ] && [ -r "$p" ] || exit 1; printf "%s\\n" "$p"',
            "kolir-path",
            target,
        ];
        pathCheckProc.running = true;
    }

    function clearCompletions() {
        root.completions = [];
        root.completionIndex = -1;
    }

    function requestCompletions() {
        if (!root.editingPath)
            return;

        const query = pathInput.text;
        completeProc.query = query;

        if (completeProc.running) {
            completeProc.restartPending = true;
            return;
        }
        root.startCompletion();
    }

    function startCompletion() {
        completeProc.activeQuery = completeProc.query;
        completeOut.runQuery = completeProc.activeQuery;
        completeProc.command = [
            "sh",
            ShellPaths.completeDirs,
            root.currentDir,
            completeProc.activeQuery,
        ];
        completeProc.running = true;
    }

    function applyCompletions(query, output) {
        // A late answer for an older draft (or a closed field) is ignored.
        if (!root.editingPath || query !== pathInput.text)
            return;

        const lines = output.split("\n").map(line => line.trim())
            .filter(line => line !== "");
        root.completions = lines.slice(0, root.maxCompletionRows);
        root.completionIndex = -1;
    }

    function completeSuggestion(index) {
        if (index < 0 || index >= root.completions.length)
            return;

        pathInput.text = root.completions[index] + "/";
        pathInput.cursorPosition = pathInput.text.length;
        root.completionIndex = -1;
        completionTimer.restart();
    }

    function chooseSuggestion(index) {
        if (index < 0 || index >= root.completions.length)
            return;

        pathInput.text = root.completions[index];
        root.submitPath();
    }
    // Set while a running folder scan is being stopped for a new directory.
    property bool restartPending: false
    // Ignore buffered stdout from the folder that is being left behind.
    property bool discardingEntries: false

    function displayName(path) {
        const name = path.substring(path.lastIndexOf("/") + 1);
        return name === "" ? path : name;
    }

    function consumeLine(line) {
        if (root.discardingEntries)
            return;

        const parts = line.split("\t");

        if (parts[0] === "dir") {
            if (parts[1])
                wallpaperModel.append({
                    kind: "dir",
                    path: parts[1],
                    thumb: "",
                    name: root.displayName(parts[1]),
                });
            return;
        }

        if (parts[0] === "total") {
            root.total = Number(parts[1]) || 0;
            return;
        }
        if (parts.length < 2 || parts[0] === "")
            return;

        const path = parts[0];
        wallpaperModel.append({
            kind: "file",
            path: path,
            thumb: parts[1] || "",
            name: root.displayName(path),
        });
        root.fileCount += 1;

        if (root.firstFileIndex < 0) {
            root.firstFileIndex = wallpaperModel.count - 1;
            grid.currentIndex = root.firstFileIndex;
        }
    }

    function resetModel() {
        wallpaperModel.clear();
        grid.currentIndex = -1;
        root.total = 0;
        root.fileCount = 0;
        root.firstFileIndex = -1;
        root.hoveredIndex = -1;
        root.scanError = "";
    }

    function beginScan() {
        root.scanning = true;
        scanProc.running = true;
    }

    function startScan() {
        if (scanProc.running)
            return;

        root.resetModel();
        root.beginScan();
    }

    function navigateTo(path) {
        if (path === "" || path === root.currentDir)
            return;

        root.currentDir = path;
        root.resetModel();

        if (scanProc.running) {
            // The worker cannot be retargeted: stop it and start the new
            // directory from onExited, so its stdout never mixes two folders.
            root.discardingEntries = true;
            root.restartPending = true;
            scanProc.running = false;
        } else {
            root.beginScan();
        }
    }

    function goUp() {
        if (root.parentDir !== "")
            root.navigateTo(root.parentDir);
    }

    function goHome() {
        root.navigateTo(ShellPaths.wallpaperDir);
    }

    function activateEntry(kind, path) {
        if (kind === "dir")
            root.navigateTo(path);
        else
            root.applyWallpaper(path);
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

        completionTimer.stop();
        root.clearCompletions();
        root.editingPath = false;
        root.pathError = "";
        if (pathCheckProc.running) {
            root.pathBusy = false;
            pathCheckProc.running = false;
        }
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

        const entry = wallpaperModel.get(grid.currentIndex);
        root.activateEntry(entry.kind, entry.path);
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

    // In the default library this stays exactly random-wallpaper.sh. In any
    // other folder, pick one of that folder's wallpapers and use the same
    // set-wallpaper.sh + generate-colors.sh chain.
    function applyRandom() {
        if (root.currentDir === ShellPaths.wallpaperDir) {
            root.close();
            randomProc.command = ["sh", ShellPaths.hyprScripts + "/random-wallpaper.sh"];
            randomProc.running = true;
            return;
        }

        const files = [];
        for (let i = 0; i < wallpaperModel.count; i++) {
            const entry = wallpaperModel.get(i);
            if (entry.kind === "file")
                files.push(entry.path);
        }
        if (files.length === 0)
            return;

        root.applyWallpaper(files[Math.floor(Math.random() * files.length)]);
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

        function openDir(path: string): void {
            root.navigateTo(path);
        }

        function up(): void {
            root.goUp();
        }

        function home(): void {
            root.goHome();
        }

        function editPath(): void {
            root.open();
            root.beginPathEdit();
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
            root.currentDir,
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
            if (root.restartPending) {
                root.restartPending = false;
                root.discardingEntries = false;
                root.resetModel();
                root.beginScan();
                return;
            }

            root.scanning = false;
            if (wallpaperModel.count > 0 && grid.currentIndex < 0)
                grid.currentIndex = 0;
        }
    }

    Process {
        id: pathCheckProc

        property string resolved: ""

        running: false

        stdout: StdioCollector {
            onStreamFinished: pathCheckProc.resolved = text.trim()
        }

        onExited: code => {
            root.pathBusy = false;

            if (!root.editingPath)
                return;

            if (code === 0 && pathCheckProc.resolved !== "") {
                completionTimer.stop();
                root.clearCompletions();
                root.editingPath = false;
                root.pathError = "";
                root.navigateTo(pathCheckProc.resolved);
                focusTimer.restart();
                return;
            }

            root.pathError = "Folder not found";
            pathInput.forceActiveFocus();
        }
    }

    Process {
        id: completeProc

        property string query: ""
        property string activeQuery: ""
        property bool restartPending: false

        running: false

        stdout: StdioCollector {
            id: completeOut

            property string runQuery: ""

            onStreamFinished: root.applyCompletions(runQuery, text)
        }

        onExited: code => {
            if (completeProc.restartPending) {
                completeProc.restartPending = false;
                root.startCompletion();
            }
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

    Timer {
        id: pathFocusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: {
            if (root.editingPath) {
                pathInput.forceActiveFocus();
                pathInput.selectAll();
            }
        }
    }

    Timer {
        id: completionTimer

        interval: root.completionDelay
        repeat: false
        onTriggered: root.requestCompletions()
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

                    Column {
                        id: titleColumn

                        anchors {
                            left: parent.left
                            leftMargin: 52
                            right: headerControls.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            text: "Wallpaper"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleSmall
                            font.weight: Typography.weight.bold
                        }

                        Item {
                            id: pathRow

                            width: parent.width
                            height: 24

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: !root.editingPath
                                text: root.currentDir
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideMiddle

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: root.beginPathEdit()
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: root.editingPath
                                radius: Dimensions.radius.small
                                color: Colors.surfaceContainerHighest
                                border.width: 1
                                border.color: root.pathError !== ""
                                    ? Colors.error
                                    : Colors.primary

                                TextInput {
                                    id: pathInput

                                    anchors {
                                        fill: parent
                                        leftMargin: 8
                                        rightMargin: 8
                                    }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.onSurface
                                    selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                                    selectedTextColor: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelMedium
                                    clip: true
                                    selectByMouse: true

                                    onTextChanged: {
                                        if (!root.editingPath)
                                            return;

                                        root.completionIndex = -1;
                                        if (text === "") {
                                            root.clearCompletions();
                                            return;
                                        }
                                        completionTimer.restart();
                                    }

                                    Keys.onPressed: event => {
                                        const count = root.completions.length;

                                        if (event.key === Qt.Key_Down && count > 0) {
                                            root.completionIndex = (root.completionIndex + 1) % count;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Up && count > 0) {
                                            root.completionIndex = root.completionIndex <= 0
                                                ? count - 1
                                                : root.completionIndex - 1;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Tab) {
                                            if (count > 0)
                                                root.completeSuggestion(root.completionIndex >= 0
                                                    ? root.completionIndex
                                                    : 0);
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Escape) {
                                            if (count > 0) {
                                                root.clearCompletions();
                                            } else {
                                                root.cancelPathEdit();
                                            }
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Return
                                                   || event.key === Qt.Key_Enter) {
                                            if (root.completionIndex >= 0 && root.completionIndex < count)
                                                root.chooseSuggestion(root.completionIndex);
                                            else
                                                root.submitPath();
                                            event.accepted = true;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        id: headerControls

                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        IconButton {
                            icon: Icons.edit
                            iconSize: Dimensions.icon.medium
                            active: root.editingPath
                            onClicked: root.editingPath
                                ? root.cancelPathEdit()
                                : root.beginPathEdit()
                        }

                        // Home always occupies the same slot to the left of
                        // Back, so navigating never shifts the Back button.
                        // In the default library it is dimmed and a click is
                        // a no-op (navigateTo already ignores the same path).
                        IconButton {
                            icon: Icons.home
                            iconSize: Dimensions.icon.medium
                            iconColor: root.currentDir === ShellPaths.wallpaperDir
                                ? Colors.withAlpha(Colors.onSurfaceVariant, 0.45)
                                : Colors.onSurface
                            onClicked: root.goHome()
                        }

                        IconButton {
                            icon: Icons.chevronUp
                            iconSize: Dimensions.icon.medium
                            visible: root.parentDir !== ""
                            onClicked: root.goUp()
                        }

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

                    onMovingChanged: {
                        if (!moving && root.hoveredIndex >= 0)
                            root.followHover(root.hoveredIndex);
                    }

                    cellWidth: root.cellWidth
                    cellHeight: root.tileHeight + root.tileSpacing

                    // Wheel degrees are always provided, including by
                    // high-resolution wheels; translate them proportionally
                    // (120 = 0.7 row) instead of stepping a whole row per
                    // fractional event. pixelDelta is only a fallback for
                    // devices that report pixels without angles.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            const pixel = event.pixelDelta.y;
                            const angle = event.angleDelta.y;

                            grid.cancelFlick();
                            if (angle !== 0)
                                grid.contentY = root.clampScroll(
                                    grid.contentY - angle / 120 * grid.cellHeight
                                        * root.wheelRowsPerNotch);
                            else if (pixel !== 0)
                                grid.contentY = root.clampScroll(grid.contentY - pixel);
                            event.accepted = true;
                        }
                    }

                    Keys.onReturnPressed: root.applyCurrent()
                    Keys.onEnterPressed: root.applyCurrent()
                    Keys.onEscapePressed: root.close()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Backspace) {
                            root.goUp();
                            event.accepted = true;
                        }
                    }

                    delegate: WallpaperTile {
                        required property int index
                        required property string kind
                        required property string path
                        required property string thumb
                        required property string name

                        width: grid.cellWidth - root.tileSpacing
                        height: grid.cellHeight - root.tileSpacing
                        thumbnailSource: thumb
                        fileName: name
                        folder: kind === "dir"
                        selected: GridView.isCurrentItem

                        // Follow the mouse with the real selection when the
                        // grid is still; scrolling under a stationary cursor
                        // must not churn currentIndex.
                        onHoveredChanged: {
                            root.hoveredIndex = hovered
                                ? index
                                : (root.hoveredIndex === index ? -1 : root.hoveredIndex);
                            if (hovered && !grid.moving)
                                root.followHover(index);
                        }

                        onActivated: root.activateEntry(kind, path)
                    }
                }

                Surface {
                    id: completionPopup

                    z: 10
                    x: 52
                    y: root.headerHeight
                    width: titleColumn.width
                    height: Math.min(root.completions.length, root.maxCompletionRows)
                        * root.completionRowHeight + 8
                    visible: root.editingPath && root.completions.length > 0
                    radius: Dimensions.radius.medium
                    surfaceColor: Colors.withAlpha(Colors.surfaceContainerHigh, 0.98)
                    borderWidth: 1
                    borderColor: Colors.withAlpha(Colors.primary, 0.35)

                    ListView {
                        anchors {
                            fill: parent
                            margins: 4
                        }
                        clip: true
                        interactive: false
                        model: root.completions

                        delegate: Rectangle {
                            id: completionRow

                            required property string modelData
                            required property int index

                            readonly property bool highlighted: index === root.completionIndex

                            width: ListView.view.width
                            height: root.completionRowHeight
                            radius: Dimensions.radius.small
                            color: completionRow.highlighted
                                ? Colors.stateLayer(Colors.primary, 0.16)
                                : "transparent"

                            Row {
                                anchors {
                                    fill: parent
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                spacing: 8

                                Text {
                                    id: completionIcon

                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Icons.folder
                                    color: completionRow.highlighted
                                        ? Colors.primary
                                        : Colors.onSurfaceVariant
                                    font.family: Typography.iconFont
                                    font.pixelSize: Dimensions.icon.small
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - completionIcon.width - parent.spacing
                                    text: completionRow.modelData
                                    color: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelSmall
                                    elide: Text.ElideMiddle
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.completionIndex = completionRow.index
                                onClicked: root.chooseSuggestion(completionRow.index)
                            }
                        }
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
                            : "No wallpapers in " + root.currentDir
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
                        text: root.pathError !== ""
                            ? root.pathError
                            : root.editingPath
                                ? (root.completions.length > 0
                                    ? "[Tab] Complete   [Up/Down] Select   [Enter] Go   [Esc] Cancel"
                                    : "[Enter] Go   [Esc] Cancel")
                                : "[Arrows] Select   [Enter] Open/Apply   [Backspace] Up   [Esc] Close"
                        color: root.pathError !== ""
                            ? Colors.error
                            : Colors.onSurfaceVariant
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
                                ? root.fileCount / root.total * 100
                                : 0
                            animated: false
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.scanning
                                ? "Previews " + root.fileCount
                                    + (root.total > 0 ? " / " + root.total : "")
                                : root.fileCount
                                    + (root.fileCount === 1 ? " wallpaper" : " wallpapers")
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
