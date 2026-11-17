import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"

// Neon-styled DBusMenu popup. Each open submenu adds a column to the left,
// keeping the root menu aligned with the tray icon that opened it.
PopupWindow {
    id: root

    property Item anchorItem: null
    property var menuStack: []

    function openFor(item, anchor) {
        if (!item || !item.hasMenu || !item.menu)
            return;

        root.menuStack = [item.menu];
        root.anchorItem = anchor;
        root.visible = true;
        focusGrab.active = true;
    }

    function closeMenu() {
        focusGrab.active = false;
        root.visible = false;
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

    visible: false
    color: "transparent"
    grabFocus: false

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.adjustment: PopupAdjustment.Slide

    implicitWidth: menuRow.implicitWidth + 4
    implicitHeight: menuRow.implicitHeight + 4

    onVisibleChanged: {
        if (!visible) {
            focusGrab.active = false;
            root.menuStack = [];
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.closeMenu()
    }

    // Dismiss the menu when clicking anywhere outside the bar or the popup.
    // PopupWindow.grabFocus is intentionally unused: a grabbing xdg_popup is
    // dismissed by the compositor as soon as it loses the implicit grab.
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root.anchor.window, root]
        onCleared: root.closeMenu()
    }

    Surface {
        anchors.fill: parent
        radius: Dimensions.radius.medium
        surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
        // Match Hyprland's focused window border: 2px in the active border color.
        borderWidth: 2
        borderColor: Colors.primary
    }

    Row {
        id: menuRow

        anchors.fill: parent
        anchors.margins: 2
        layoutDirection: Qt.RightToLeft
        spacing: 0

        Repeater {
            model: root.menuStack

            delegate: TrayMenuPane {
                id: pane

                required property var modelData
                required property int index

                width: 220
                height: pane.implicitHeight

                menuHandle: modelData
                depth: index
                openEntry: root.menuStack.length > index + 1
                    ? root.menuStack[index + 1]
                    : null

                onEntryHovered: entry => root.expand(index, entry)
                onEntryActivated: Qt.callLater(root.closeMenu)
            }
        }
    }
}
