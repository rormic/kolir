pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../theme"

// System tray menu sheet. It is the same EmbeddedSheet as the night-light,
// sound, battery, notification and calendar sheets — same surface, scrim,
// reveal and dismissal — floating under the tray icon that opened it. The root
// card is centered under that icon: a submenu extends the panel to the left
// and leaves the root column where it was, so the icon stays over the middle
// of the menu instead of over one edge.
//
// Each level of the DBusMenu tree is one framed column: the root menu sits
// under the icon and every open submenu adds a column to its left. Hovering a
// parent expands it, hovering a sibling collapses the deeper columns, and a
// leaf triggers its DBusMenu action and closes the sheet.
EmbeddedSheet {
    id: root

    // Set by Tray.qml before opening.
    property var trayItem: null
    // Root menu plus one entry per open submenu. Each item is a QsMenuHandle.
    property var menuStack: []
    // Center of the clicked tray icon in bar coordinates. -1 keeps the
    // edge-sheet behaviour while the menu is closed.
    property real iconCenterX: -1

    // The whole panel is positioned so the root column's center (not its
    // edge) sits under the icon. The root column is the rightmost one, so
    // opening a submenu grows the panel left and leaves the root column in
    // place; the decorative right shoulder still extends one panelFlare past
    // the card's right edge.
    anchorCenterX: root.iconCenterX >= 0
        ? root.iconCenterX + root.contentRightInset + root.columnWidth / 2
            - root.popupWidth / 2
        : -1

    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 12
    readonly property int contentBottomReserve: 6
    readonly property int columnSpacing: 8
    readonly property int preferredColumnWidth: 220
    readonly property int maxPanelWidth: Math.max(280, root.width - 24)
    // Long menus scroll inside the panel instead of running down the screen.
    readonly property int maxPanelHeight: Math.min(720, Math.max(
        320, root.height - Dimensions.bar.height - 8))

    readonly property int columnCount: Math.max(1, root.menuStack.length)
    // The panel grows with the open columns. The row below divides the actual
    // content width, so a clamped panel keeps every column usable.
    popupWidth: Math.min(root.maxPanelWidth, 2 * root.panelFlare
        + root.columnCount * root.preferredColumnWidth
        + (root.columnCount - 1) * root.columnSpacing)
    readonly property real columnWidth: Math.max(120,
        (root.popupWidth - root.contentLeftInset - root.contentRightInset
         - (root.columnCount - 1) * root.columnSpacing) / root.columnCount)

    readonly property string titleText: root.trayItem
        ? (root.trayItem.title || root.trayItem.tooltipTitle || "System tray")
        : "System tray"
    readonly property string subtitleText: {
        if (root.menuStack.length > 1) {
            const entry = root.menuStack[root.menuStack.length - 1];
            if (entry && entry.text)
                return entry.text;
        }

        return root.trayItem && root.trayItem.tooltipDescription
            ? root.trayItem.tooltipDescription
            : "System tray menu";
    }

    panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + menuRow.implicitHeight + root.contentBottomReserve)

    // A submenu can be taller than the root menu, so grow the sheet instead of
    // jumping; the width grows leftwards from the pinned right edge.
    Behavior on panelHeight {
        enabled: root.opened

        NumberAnimation {
            duration: Motion.move
            easing.type: Easing.OutCubic
        }
    }

    Behavior on popupWidth {
        enabled: root.opened

        NumberAnimation {
            duration: Motion.move
            easing.type: Easing.OutCubic
        }
    }

    function openFor(item, anchor) {
        if (!item || !anchor || !item.hasMenu || !item.menu)
            return;

        const point = anchor.mapToItem(null, anchor.width / 2, 0);
        const switching = root.opened;

        root.trayItem = item;
        root.iconCenterX = point.x;
        root.menuStack = [item.menu];

        if (!switching)
            root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        root.revealClose();
    }

    function toggleFor(item, anchor) {
        if (root.opened && root.trayItem === item) {
            root.close();
            return;
        }

        root.openFor(item, anchor);
    }

    function expand(index, entry) {
        if (!entry || !entry.hasChildren) {
            root.menuStack = root.menuStack.slice(0, index + 1);
            return;
        }

        const next = root.menuStack.slice(0, index + 1);
        next.push(entry);
        root.menuStack = next;
    }

    onDismissalRequested: root.close()

    onDidClose: {
        root.menuStack = [];
        root.trayItem = null;
        root.iconCenterX = -1;
    }

    Keys.onEscapePressed: function (event) {
        root.close();
        event.accepted = true;
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + root.contentColumnMargins
            leftMargin: root.contentColumnMargins
            rightMargin: root.contentColumnMargins
            bottomMargin: root.contentColumnMargins
        }
        spacing: root.contentColumnSpacing

        PopupHeader {
            Layout.fillWidth: true
            Layout.preferredHeight: root.titleBlockHeight
            title: root.titleText
            subtitle: root.subtitleText
        }

        Flickable {
            id: menuFlick

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: menuRow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: menuRow

                width: menuFlick.width
                height: implicitHeight
                layoutDirection: Qt.RightToLeft
                spacing: root.columnSpacing

                Repeater {
                    model: root.menuStack

                    delegate: TrayMenuPane {
                        id: pane

                        required property var modelData
                        required property int index

                        width: root.columnWidth
                        height: pane.implicitHeight

                        menuHandle: modelData
                        openEntry: root.menuStack.length > index + 1
                            ? root.menuStack[index + 1]
                            : null

                        onEntryHovered: entry => root.expand(index, entry)
                        onEntryActivated: root.close()
                    }
                }
            }
        }
    }
}
