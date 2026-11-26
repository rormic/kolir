pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../theme"

// One framed column of a DBusMenu tree. TrayMenu lays the columns out to the
// left of the root pane, so a submenu never pushes the root menu away from its
// tray icon. The rows use the same hover state layer and framed list surface
// as the device and notification lists in the other sheets.
Item {
    id: root

    property var menuHandle: null
    property var openEntry: null

    signal entryHovered(var entry)
    signal entryActivated()

    implicitWidth: 220
    implicitHeight: Math.max(8, list.implicitHeight + 8)

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    Rectangle {
        anchors.fill: parent
        radius: Dimensions.radius.medium
        color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
    }

    Column {
        id: list

        anchors {
            fill: parent
            margins: 4
        }
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
                // DBusMenu carries an absolute path, a themed icon name or a
                // Quickshell image://icon/ URL. Resolve the name against the
                // active theme and hide it when the theme does not have it,
                // instead of drawing the broken-image fallback.
                readonly property string iconName: {
                    const icon = row.entry.icon ? String(row.entry.icon) : "";
                    return icon.startsWith("image://icon/")
                        ? icon.substring("image://icon/".length)
                        : icon;
                }
                readonly property string iconSource: {
                    const icon = row.iconName;
                    if (icon.length === 0)
                        return "";
                    if (icon.startsWith("/"))
                        return icon;
                    return Quickshell.hasThemeIcon(icon)
                        ? Quickshell.iconPath(icon, "")
                        : "";
                }

                width: list.width
                height: row.entry.isSeparator ? 9 : 34
                opacity: row.entry.enabled ? 1.0 : 0.55

                Rectangle {
                    visible: row.entry.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: 1
                    color: Colors.withAlpha(Colors.outlineVariant, 0.3)
                }

                Rectangle {
                    anchors {
                        fill: parent
                        margins: 2
                    }
                    visible: !row.entry.isSeparator
                    radius: Dimensions.radius.small
                    color: "transparent"

                    StateLayer {
                        shown: row.entry.enabled && (row.hovered || row.submenuOpen)
                        tint: row.submenuOpen ? Colors.primary : Colors.onSurface
                        strength: row.submenuOpen ? 0.12 : 0.07
                    }
                }

                Item {
                    id: leading

                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    visible: !row.entry.isSeparator

                    Image {
                        anchors.fill: parent
                        source: row.iconSource
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
                    color: row.submenuOpen
                        ? Colors.primary
                        : row.entry.enabled
                            ? Colors.onSurface
                            : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: row.submenuOpen
                        ? Typography.weight.bold
                        : Typography.weight.medium
                    elide: Text.ElideRight

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.hover
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.standardDecelerateCurve
                        }
                    }
                }

                Item {
                    id: trailing

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 12 : 0
                    height: 16
                    visible: !row.entry.isSeparator && row.entry.hasChildren

                    Text {
                        anchors.centerIn: parent
                        // Submenus open as columns to the left.
                        text: Icons.chevronLeft
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

                    // Let the sheet's Flickable handle the wheel instead of
                    // swallowing it on the row.
                    onWheel: wheel => wheel.accepted = false

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
