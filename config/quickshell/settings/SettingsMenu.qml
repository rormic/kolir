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

    readonly property int popupWidth: 380
    readonly property int mainHeight: 164
    readonly property int bluetoothHeight: 520

    function open(page) {
        root.page = page ?? "main";
        popup.visible = true;
        grab.active = true;
    }

    function close() {
        popup.visible = false;
        grab.active = false;
        root.page = "main";
    }

    function toggle() {
        if (popup.visible)
            root.close();
        else
            root.open("main");
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

        function close(): void {
            root.close();
        }
    }

    IconButton {
        id: button

        anchors.centerIn: parent
        icon: Icons.settings
        iconSize: Dimensions.icon.large
        active: popup.visible
        onClicked: root.toggle()
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: false

        anchor.item: button
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.Slide

        implicitWidth: root.popupWidth
        implicitHeight: root.page === "main" ? root.mainHeight : root.bluetoothHeight

        onVisibleChanged: if (!visible) root.page = "main"

        Surface {
            anchors.fill: parent
            radius: Dimensions.radius.extraLarge
            surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
            borderColor: Colors.withAlpha(Colors.outlineVariant, 0.18)
        }

        // Signature neon line, same as the bar and tray menus.
        Rectangle {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.2; color: Colors.withAlpha(Colors.primary, 0.35) }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.primary, 0.85) }
                GradientStop { position: 0.8; color: Colors.withAlpha(Colors.primary, 0.35) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Item {
            anchors.fill: parent

            MainPage {
                anchors.fill: parent
                visible: root.page === "main"
                onOpen: page => root.page = page
            }

            BluetoothPage {
                anchors.fill: parent
                visible: root.page === "bluetooth"
                onBack: root.page = "main"
                onClose: root.close()
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
        enabled: popup.visible
        onActivated: {
            if (root.page === "bluetooth")
                root.page = "main";
            else
                root.close();
        }
    }

    // Main settings grid. Entries are data-driven so future categories only
    // need an object here plus their own page component.
    component MainPage: Item {
        id: mainPage

        signal open(string page)

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
                title: "Wi-Fi",
                subtitle: "Soon",
                soon: true,
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
                        readonly property bool soon: modelData.soon

                        width: 108
                        height: 96

                        Rectangle {
                            anchors.fill: parent
                            radius: Dimensions.radius.medium
                            color: tileMouse.containsMouse && !tile.soon
                                ? Colors.stateLayer(Colors.onSurface, 0.07)
                                : Colors.surfaceContainerHigh
                            border.width: (tile.soon || tileMouse.containsMouse) ? 1 : 0
                            border.color: tile.soon
                                ? Colors.withAlpha(Colors.outlineVariant, 0.45)
                                : Colors.withAlpha(Colors.primary, 0.6)

                            Behavior on color { ColorAnimation { duration: 130 } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.icon
                                color: tile.soon ? Colors.onSurfaceVariant : Colors.primary
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.extraLarge
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.title
                                color: Colors.onSurface
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
