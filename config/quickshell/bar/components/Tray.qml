import QtQuick
import Quickshell.Services.SystemTray
import "../../theme"

// System tray icons. Kept as a separate row so an empty tray takes no space.
Item {
    id: root

    property var activeItem: null

    readonly property int itemCount: repeater.count

    implicitWidth: row.implicitWidth
    implicitHeight: Dimensions.bar.height
    visible: repeater.count > 0

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
                menuOpen: root.activeItem === modelData && trayMenu.visible

                onMenuRequested: (item, anchor) => {
                    if (trayMenu.visible && root.activeItem === item) {
                        trayMenu.closeMenu();
                        return;
                    }

                    root.activeItem = item;
                    trayMenu.openFor(item, anchor);
                }
            }
        }
    }

    TrayMenu {
        id: trayMenu
        onVisibleChanged: if (!visible) root.activeItem = null
    }

    // The focus grab may hand keyboard focus to the bar instead of the popup.
    Shortcut {
        sequence: "Escape"
        enabled: trayMenu.visible
        onActivated: trayMenu.closeMenu()
    }
}
