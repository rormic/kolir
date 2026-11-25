pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import "../../theme"

// System tray icons. Kept as a separate row so an empty tray takes no space.
// The menu is the shared floating TrayMenu sheet, instantiated by Bar.qml as an
// overlay on the bar surface instead of a separate popup window.
Item {
    id: root

    // Assigned by Bar.qml: the TrayMenu sheet that owns the open menu.
    property TrayMenu menu: null

    implicitWidth: row.implicitWidth
    implicitHeight: Dimensions.bar.height
    visible: repeater.count > 0

    function toggleMenu(item, anchor) {
        if (!root.menu)
            return;

        root.menu.toggleFor(item, anchor);
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Repeater {
            id: repeater
            model: SystemTray.items

            delegate: TrayButton {
                required property var modelData

                trayItem: modelData
                menuOpen: root.menu !== null && root.menu.modal
                    && root.menu.trayItem === modelData

                onMenuRequested: (item, anchor) => root.toggleMenu(item, anchor)
            }
        }
    }
}
