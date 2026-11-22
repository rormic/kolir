pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../services"
import "../theme"

// Capture history overlay. Lists the newest screenshots and recordings from
// the folders written by screenshot-region.sh and screen-record.sh, newest
// first, with cached 16:9 posters from scripts/capture-history.sh.
//
// The panel follows WallpaperPicker's contract: a full-screen Overlay with
// exclusive keyboard focus, Escape/outside-click dismissal, arrow selection,
// and a keyboard-friendly action set (Enter opens, C copies, Delete asks once
// more before removing the file). The service polls while the panel is open,
// so a capture that lands meanwhile shows up without a shell restart.
Scope {
    id: root

    // ── Panel geometry ───────────────────────────────────────────────────
    readonly property int panelWidth: 1120
    readonly property int panelHeight: 780
    readonly property int screenMargin: 48
    readonly property int headerHeight: 56
    readonly property int footerHeight: 44
    readonly property int contentPadding: 16
    readonly property int tileSpacing: 12
    readonly property int gridColumns: 4
    // Mirror CaptureTile.qml's chrome so a cell reserves exactly the space the
    // card needs for its poster, inset and two label lines.
    readonly property int tileInset: 6
    readonly property int tileLabelHeight: 40
    readonly property real thumbnailAspect: 16 / 9
    readonly property int focusDelay: 20
    readonly property int statusDuration: 2600
    readonly property int deleteConfirmDuration: 6000
    readonly property int prefetchRows: 1
    readonly property real wheelRowsPerNotch: 0.7

    readonly property real cellWidth: Math.floor(
        (panel.width - root.contentPadding * 2) / root.gridColumns)
    readonly property real tileWidth: root.cellWidth - root.tileSpacing
    readonly property real tileImageHeight: Math.round(root.tileWidth / root.thumbnailAspect)
    readonly property real tileHeight: root.tileImageHeight
        + root.tileLabelHeight + root.tileInset * 2 + root.tileInset / 2

    // 0 = hidden, 1 = fully visible. The window stays mapped at full screen,
    // only the panel fades/slides so Wayland never sees a resize.
    property real reveal: 0
    property string pendingDeletePath: ""
    property string statusMessage: ""
    property int hoveredIndex: -1

    function displayName(path) {
        const name = path.substring(path.lastIndexOf("/") + 1);
        return name === "" ? path : name;
    }

    function followHover(index) {
        if (index < 0 || index >= CaptureHistoryService.count)
            return;
        grid.currentIndex = index;
    }

    function currentEntry() {
        if (grid.currentIndex < 0 || grid.currentIndex >= CaptureHistoryService.count)
            return null;
        return CaptureHistoryService.entries[grid.currentIndex];
    }

    function showStatus(message) {
        root.statusMessage = message;
        statusTimer.restart();
    }

    function cancelDelete() {
        deleteTimer.stop();
        root.pendingDeletePath = "";
    }

    function copyCurrent() {
        const entry = root.currentEntry();
        if (entry === null)
            return;
        CaptureHistoryService.copy(entry.path, entry.kind);
    }

    function openCurrent() {
        const entry = root.currentEntry();
        if (entry === null)
            return;
        root.close();
        CaptureHistoryService.open(entry.path);
    }

    function requestDeleteCurrent() {
        const entry = root.currentEntry();
        if (entry === null)
            return;

        // A second Delete within the confirmation window really removes the
        // file; the first one only arms the card.
        if (root.pendingDeletePath === entry.path) {
            root.cancelDelete();
            CaptureHistoryService.remove(entry.path);
            return;
        }

        root.pendingDeletePath = entry.path;
        deleteTimer.restart();
    }

    function clampScroll(y) {
        const max = Math.max(0, grid.contentHeight - grid.height);
        return Math.max(0, Math.min(max, y));
    }

    function open() {
        CaptureHistoryService.setActive(true);
        root.cancelDelete();
        root.statusMessage = "";

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

        root.cancelDelete();
        statusTimer.stop();
        root.statusMessage = "";
        CaptureHistoryService.setActive(false);
        revealIn.stop();
        revealOut.restart();
    }

    function toggle() {
        if (win.visible && root.reveal > 0.5)
            root.close();
        else
            root.open();
    }

    IpcHandler {
        target: "captureHistory"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function refresh(): void {
            CaptureHistoryService.refresh();
        }
    }

    Connections {
        target: CaptureHistoryService

        function onCopied(path, kind) {
            root.showStatus(kind === "video" ? "Path copied" : "Image copied");
        }

        function onDeleted(path) {
            root.showStatus("Deleted " + root.displayName(path));
        }

        function onOpenFailed(path) {
            root.showStatus("Could not open " + root.displayName(path));
        }

        function onActionFailed(message) {
            root.showStatus(message);
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
        id: statusTimer

        interval: root.statusDuration
        repeat: false
        onTriggered: root.statusMessage = ""
    }

    Timer {
        id: deleteTimer

        interval: root.deleteConfirmDuration
        repeat: false
        onTriggered: root.pendingDeletePath = ""
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
        WlrLayershell.namespace: "capture-history"
        WlrLayershell.exclusiveZone: 0

        onVisibleChanged: {
            if (!visible) {
                revealIn.stop();
                revealOut.stop();
                root.reveal = 0;
            }
        }

        // Clicking anywhere outside the panel dismisses it without changing
        // anything.
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
                        text: Icons.photoLibrary
                        color: Colors.primary
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.extraLarge
                    }

                    Column {
                        anchors {
                            left: parent.left
                            leftMargin: 52
                            right: headerControls.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            text: "Capture History"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleSmall
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            width: parent.width
                            text: CaptureHistoryService.scanning
                                    && CaptureHistoryService.count === 0
                                ? "Preparing previews… "
                                    + CaptureHistoryService.loaded
                                    + (CaptureHistoryService.total > 0
                                        ? " / " + CaptureHistoryService.total : "")
                                : CaptureHistoryService.count
                                    + (CaptureHistoryService.count === 1
                                        ? " item" : " items")
                                    + " · newest first"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
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
                            icon: Icons.refresh
                            iconSize: Dimensions.icon.medium
                            onClicked: CaptureHistoryService.refresh()
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
                    model: CaptureHistoryService.entries
                    currentIndex: -1
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: root.tileHeight * root.prefetchRows

                    onCountChanged: {
                        if (count === 0)
                            grid.currentIndex = -1;
                        else if (grid.currentIndex < 0)
                            grid.currentIndex = 0;
                        else if (grid.currentIndex >= count)
                            grid.currentIndex = count - 1;
                    }

                    onMovingChanged: {
                        if (!moving && root.hoveredIndex >= 0)
                            root.followHover(root.hoveredIndex);
                    }

                    cellWidth: root.cellWidth
                    cellHeight: root.tileHeight + root.tileSpacing

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

                    Keys.onReturnPressed: root.openCurrent()
                    Keys.onEnterPressed: root.openCurrent()
                    Keys.onEscapePressed: {
                        if (root.pendingDeletePath !== "")
                            root.cancelDelete();
                        else
                            root.close();
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_C) {
                            root.copyCurrent();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Delete) {
                            root.requestDeleteCurrent();
                            event.accepted = true;
                        }
                    }

                    delegate: CaptureTile {
                        required property int index
                        // The records arrive as plain objects (a singleton's
                        // model does not expose per-key roles to a delegate),
                        // so the card values are bound explicitly.
                        required property var modelData

                        width: grid.cellWidth - root.tileSpacing
                        height: grid.cellHeight - root.tileSpacing
                        path: modelData.path
                        thumb: modelData.thumb
                        kind: modelData.kind
                        mtime: modelData.mtime
                        fileName: root.displayName(modelData.path)
                        selected: GridView.isCurrentItem
                        confirmingDelete: modelData.path === root.pendingDeletePath

                        onHoveredChanged: {
                            root.hoveredIndex = hovered
                                ? index
                                : (root.hoveredIndex === index ? -1 : root.hoveredIndex);
                            if (hovered && !grid.moving)
                                root.followHover(index);
                        }

                        onActivated: {
                            grid.currentIndex = index;
                            root.openCurrent();
                        }

                        onCopyRequested: CaptureHistoryService.copy(modelData.path, modelData.kind)

                        onDeleteRequested: {
                            grid.currentIndex = index;
                            root.requestDeleteCurrent();
                        }

                        onCancelDelete: root.cancelDelete()
                    }
                }

                Column {
                    anchors.centerIn: grid
                    spacing: 10
                    visible: CaptureHistoryService.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: CaptureHistoryService.scanning
                            ? Icons.photoLibrary
                            : CaptureHistoryService.error !== ""
                                ? Icons.warning
                                : Icons.searchOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: 32
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: CaptureHistoryService.scanning
                            ? "Preparing previews…"
                            : CaptureHistoryService.error !== ""
                                ? CaptureHistoryService.error
                                : "No screenshots or recordings yet"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !CaptureHistoryService.scanning
                            && CaptureHistoryService.error === ""
                        text: "New captures appear here automatically"
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
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
                            right: footerInfo.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.statusMessage !== ""
                            ? root.statusMessage
                            : root.pendingDeletePath !== ""
                                ? "Press Del again to delete · Esc cancels"
                                : "[Arrows] Select   [Enter] Open   [C] Copy   [Del] Delete   [Esc] Close"
                        color: root.statusMessage !== ""
                            ? Colors.primary
                            : root.pendingDeletePath !== ""
                                ? Colors.error
                                : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }

                    Row {
                        id: footerInfo

                        anchors {
                            right: parent.right
                            rightMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        ProgressIndicator {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120
                            visible: CaptureHistoryService.scanning
                                && CaptureHistoryService.count === 0
                            value: CaptureHistoryService.total > 0
                                ? CaptureHistoryService.loaded / CaptureHistoryService.total * 100
                                : 0
                            animated: false
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: CaptureHistoryService.count
                                + (CaptureHistoryService.count === 1 ? " item" : " items")
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
