pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../theme"
import "ShortcutParser.js" as ShortcutParser

// Keyboard shortcut cheat sheet, opened with SUPER+D. The list is live: every
// open re-reads `hyprctl binds -j`, so binds added in hyprland.lua or
// user.lua (with a `description`) show up without touching the shell.
//
// Binds are grouped by their modifier set ("Super", "Super + Shift",
// "Hardware keys", …), because Hyprland's Lua config reports the dispatcher
// but not its argument, leaving the description as the only readable action
// name. Rows keep just the key chip and the description.
//
// Escape, the close button and an outside click dismiss the panel; nothing
// else happens on dismissal.
Scope {
    id: root

    // ── Panel geometry ───────────────────────────────────────────────────
    readonly property int panelWidth: 900
    readonly property int panelHeight: 740
    readonly property int screenMargin: 40
    readonly property int headerHeight: 58
    readonly property int searchHeight: 44
    readonly property int footerHeight: 40
    readonly property int groupHeaderHeight: 28
    readonly property int groupSpacing: 16
    readonly property int contentPadding: 14
    readonly property int focusDelay: 20
    readonly property int scrollStep: 54

    // 0 = hidden, 1 = fully visible. The window stays mapped at full screen,
    // only the card fades/slides so Wayland never sees a resize.
    property real reveal: 0

    property string bindsJson: ""
    property bool loading: false
    property string loadError: ""
    property var groups: []
    property int total: 0

    readonly property string filter: searchField.text.trim()

    function refresh() {
        root.loading = true;
        root.loadError = "";
        loadTimer.restart();
        bindsProc.running = true;
    }

    function applyBinds(output) {
        root.bindsJson = output;
        root.rebuild();
    }

    function rebuild() {
        const parsed = ShortcutParser.parse(root.bindsJson, root.filter);

        root.groups = parsed.groups;
        root.total = parsed.total;
        root.loadError = parsed.error;
    }

    function scrollBy(dy) {
        const max = Math.max(0, contentFlick.contentHeight - contentFlick.height);

        contentFlick.contentY = Math.max(0, Math.min(max, contentFlick.contentY + dy));
    }

    function open() {
        if (win.visible && root.reveal >= 1) {
            searchField.forceActiveFocus();
            return;
        }

        // A reopen while the card is still fading out only reverses the
        // animation; the already loaded list must not flash empty.
        if (!win.visible) {
            root.groups = [];
            root.total = 0;
            root.loadError = "";
            root.bindsJson = "";
            searchField.text = "";
            win.visible = true;
            root.refresh();
        }

        revealOut.stop();
        revealIn.restart();
        focusTimer.restart();
    }

    function close() {
        revealIn.stop();
        revealOut.restart();
    }

    function toggle() {
        if (root.reveal > 0.5)
            root.close();
        else
            root.open();
    }

    IpcHandler {
        target: "shortcuts"

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

    Process {
        id: bindsProc

        running: false
        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: root.applyBinds(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "")
                    console.warn("Shortcuts:", message);
            }
        }

        onExited: code => {
            loadTimer.stop();
            root.loading = false;
            if (code !== 0 && root.loadError === "")
                root.loadError = "Could not read the Hyprland bind list";
        }
    }

    // hyprctl normally answers in a few milliseconds. The timeout only keeps
    // the panel from sitting on "Loading…" when the process cannot start at
    // all (for example on a session without Hyprland).
    Timer {
        id: loadTimer

        interval: 4000
        repeat: false
        onTriggered: {
            if (root.loading) {
                root.loading = false;
                root.loadError = "hyprctl did not answer";
            }
        }
    }

    NumberAnimation {
        id: revealIn

        target: root
        property: "reveal"
        to: 1
        duration: Motion.popupEnter
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.emphasizedDecelerateCurve
    }

    NumberAnimation {
        id: revealOut

        target: root
        property: "reveal"
        to: 0
        duration: Motion.popupExit
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.emphasizedAccelerateCurve

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
        onTriggered: searchField.forceActiveFocus()
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
        WlrLayershell.namespace: "shortcuts"
        WlrLayershell.exclusiveZone: 0

        onVisibleChanged: {
            if (!visible) {
                revealIn.stop();
                revealOut.stop();
                root.reveal = 0;
            }
        }

        // Clicking outside the card dismisses the cheat sheet.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            anchors.fill: parent
            opacity: root.reveal
            scale: 0.97 + 0.03 * root.reveal
            transformOrigin: Item.Center
            transform: Translate { y: -(1.0 - root.reveal) * 10 }

            Surface {
                id: panel

                anchors.centerIn: parent
                width: Math.min(root.panelWidth, win.width - root.screenMargin * 2)
                height: Math.min(root.panelHeight, win.height - root.screenMargin * 2)
                radius: Dimensions.radius.extraLarge
                surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
                borderWidth: 2
                borderColor: Colors.primary

                // Clicks inside the card must not reach the dismissal layer.
                MouseArea {
                    anchors.fill: parent
                }

                // ── Header ───────────────────────────────────────────────
                Item {
                    id: header

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
                        text: Icons.keyboard
                        color: Colors.primary
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.extraLarge
                    }

                    Column {
                        anchors {
                            left: parent.left
                            leftMargin: 52
                            right: closeButton.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            text: "Keyboard shortcuts"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleSmall
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            width: parent.width
                            text: root.loading
                                ? "Reading the Hyprland bind list…"
                                : root.loadError !== ""
                                    ? root.loadError
                                    : (root.total + (root.total === 1 ? " shortcut" : " shortcuts")
                                        + " · grouped by modifier")
                            color: root.loadError !== "" ? Colors.error : Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        id: closeButton

                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        icon: Icons.close
                        iconSize: Dimensions.icon.large
                        iconColor: Colors.onSurfaceVariant
                        onClicked: root.close()
                    }
                }

                // ── Filter ───────────────────────────────────────────────
                Rectangle {
                    id: searchRow

                    anchors {
                        top: header.bottom
                        left: parent.left
                        leftMargin: 18
                        right: parent.right
                        rightMargin: 18
                    }
                    height: root.searchHeight - 4
                    radius: Dimensions.radius.full
                    color: Colors.withAlpha(Colors.surfaceContainerHigh, 0.85)
                    border.width: 1
                    border.color: searchField.activeFocus
                        ? Colors.withAlpha(Colors.primary, 0.65)
                        : Colors.withAlpha(Colors.outlineVariant, 0.25)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Motion.color
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.standardDecelerateCurve
                        }
                    }

                    Text {
                        id: searchIcon

                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        text: Icons.search
                        color: searchField.activeFocus ? Colors.primary : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: 18

                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.color
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }
                    }

                    Text {
                        anchors {
                            left: searchIcon.right
                            leftMargin: 10
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        visible: searchField.text === ""
                        text: "Filter shortcuts…"
                        color: Colors.onSurfaceVariant
                        opacity: 0.78
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        elide: Text.ElideRight
                    }

                    TextInput {
                        id: searchField

                        anchors {
                            left: searchIcon.right
                            leftMargin: 10
                            right: parent.right
                            rightMargin: 14
                            top: parent.top
                            bottom: parent.bottom
                        }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.onSurface
                        selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                        selectedTextColor: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        clip: true

                        HoverHandler {
                            cursorShape: Qt.IBeamCursor
                        }

                        onTextChanged: {
                            root.rebuild();
                            contentFlick.contentY = 0;
                        }

                        Keys.onEscapePressed: root.close()
                        Keys.onUpPressed: root.scrollBy(-root.scrollStep)
                        Keys.onDownPressed: root.scrollBy(root.scrollStep)
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_PageUp)
                                root.scrollBy(-contentFlick.height * 0.8);
                            else if (event.key === Qt.Key_PageDown)
                                root.scrollBy(contentFlick.height * 0.8);
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                }

                // ── Shortcut list ────────────────────────────────────────
                Flickable {
                    id: contentFlick

                    anchors {
                        top: searchRow.bottom
                        topMargin: 10
                        left: parent.left
                        leftMargin: 22
                        right: parent.right
                        rightMargin: 22
                        bottom: footer.top
                    }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight + root.contentPadding

                    Column {
                        id: contentColumn

                        width: contentFlick.width
                        spacing: 0

                        Repeater {
                            model: root.groups

                            delegate: Column {
                                id: groupColumn

                                required property var modelData
                                required property int index

                                width: contentColumn.width
                                topPadding: index === 0 ? 0 : root.groupSpacing

                                Item {
                                    width: groupColumn.width
                                    height: root.groupHeaderHeight

                                    Text {
                                        anchors {
                                            left: parent.left
                                            leftMargin: 8
                                            right: groupCount.left
                                            rightMargin: 8
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: groupColumn.modelData.title
                                        color: Colors.primary
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelLarge
                                        font.weight: Typography.weight.bold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: groupCount

                                        anchors {
                                            right: parent.right
                                            rightMargin: 10
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: groupColumn.modelData.shortcuts.length
                                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelSmall
                                    }
                                }

                                Repeater {
                                    model: groupColumn.modelData.shortcuts

                                    delegate: ShortcutRow {
                                        required property var modelData

                                        width: groupColumn.width
                                        keyLabel: modelData.key
                                        description: modelData.description
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Empty / loading state ────────────────────────────────
                Column {
                    anchors.centerIn: contentFlick
                    spacing: 8
                    visible: root.groups.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.loadError !== ""
                            ? Icons.warning
                            : (root.loading ? Icons.schedule : Icons.searchOff)
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: 28
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.loadError !== ""
                            ? "No shortcuts to show"
                            : root.loading
                                ? "Loading…"
                                : "No shortcuts match “" + root.filter + "”"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }

                // ── Footer ───────────────────────────────────────────────
                Item {
                    id: footer

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: root.footerHeight

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            leftMargin: 18
                            right: parent.right
                            rightMargin: 18
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.2)
                    }

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 22
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        KeyChip {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            horizontalPadding: 7
                            labelSize: Typography.size.labelSmall
                            label: "Esc"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "close"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }
                    }

                    Row {
                        anchors {
                            right: parent.right
                            rightMargin: 22
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "type to filter"
                            color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }
                    }
                }
            }
        }
    }
}
