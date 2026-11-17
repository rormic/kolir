import QtQuick
import Quickshell
import "../../theme"

// One column of a DBusMenu tree. Submenus are rendered as additional columns
// by TrayMenu, which keeps the whole menu inside a single popup window.
Item {
    id: root

    property var menuHandle: null
    property int depth: 0
    property var openEntry: null

    signal entryHovered(var entry)
    signal entryActivated()

    implicitWidth: 220
    implicitHeight: Math.max(8, list.implicitHeight + 8)

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    // Divider between the menu and an open submenu.
    Rectangle {
        visible: root.depth > 0
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Colors.withAlpha(Colors.outlineVariant, 0.24)
    }

    Column {
        id: list

        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.right: parent.right
        anchors.rightMargin: 4
        spacing: 0

        Repeater {
            model: opener.children

            delegate: Item {
                id: row

                required property var modelData

                readonly property var entry: modelData
                readonly property bool hovered: rowMouse.containsMouse
                readonly property bool submenuOpen: root.openEntry !== null
                    && root.openEntry === row.entry
                readonly property bool checkable: row.entry.buttonType
                    !== QsMenuButtonType.None
                readonly property bool checked: row.entry.checkState === Qt.Checked
                readonly property bool partiallyChecked: row.entry.checkState
                    === Qt.PartiallyChecked

                width: list.width
                height: row.entry.isSeparator ? 9 : 28
                opacity: row.entry.enabled ? 1.0 : 0.55

                Rectangle {
                    visible: row.entry.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: 1
                    color: Colors.withAlpha(Colors.outlineVariant, 0.45)
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !row.entry.isSeparator && (row.hovered || row.submenuOpen)
                    radius: Dimensions.radius.small - 2
                    color: row.submenuOpen
                        ? Colors.stateLayer(Colors.primary, 0.14)
                        : Colors.stateLayer(Colors.onSurface, 0.07)
                    border.width: row.submenuOpen ? 1 : 0
                    border.color: Colors.withAlpha(Colors.primary, 0.45)
                    Behavior on color { ColorAnimation { duration: 110 } }
                }

                Item {
                    id: leading

                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    visible: !row.entry.isSeparator

                    Image {
                        anchors.fill: parent
                        source: row.entry.icon ?? ""
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: source !== "" && status === Image.Ready
                            && !row.checkable
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: row.checkable && (row.checked
                            || row.entry.buttonType === QsMenuButtonType.RadioButton)
                        text: row.entry.buttonType === QsMenuButtonType.RadioButton
                            ? (row.checked ? Icons.radioChecked : Icons.radioUnchecked)
                            : (row.partiallyChecked ? Icons.remove : Icons.check)
                        color: row.checked
                            ? Colors.primary
                            : Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                }

                Text {
                    id: label

                    anchors.left: leading.right
                    anchors.leftMargin: 8
                    anchors.right: trailing.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.entry.isSeparator
                    text: row.entry.text
                    color: row.entry.enabled
                        ? (row.submenuOpen ? Colors.primary : Colors.onSurface)
                        : Colors.withAlpha(Colors.onSurfaceVariant, 0.45)
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: row.submenuOpen
                        ? Typography.weight.bold
                        : Typography.weight.medium
                    elide: Text.ElideRight

                    Behavior on color { ColorAnimation { duration: 110 } }
                }

                Item {
                    id: trailing

                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 12 : 0
                    height: 16
                    visible: !row.entry.isSeparator && row.entry.hasChildren

                    Text {
                        anchors.centerIn: parent
                        text: Icons.chevronRight
                        color: row.submenuOpen
                            ? Colors.primary
                            : Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium
                    }
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    enabled: !row.entry.isSeparator && row.entry.enabled
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: row.entry.enabled && !row.entry.isSeparator
                        ? Qt.PointingHandCursor
                        : Qt.ArrowCursor

                    onContainsMouseChanged: {
                        if (containsMouse)
                            root.entryHovered(row.entry);
                    }

                    onClicked: {
                        if (row.entry.hasChildren) {
                            root.entryHovered(row.entry);
                        } else {
                            row.entry.triggered();
                            root.entryActivated();
                        }
                    }
                }
            }
        }
    }
}
