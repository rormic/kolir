import QtQuick
import "../../theme"

// Neon accent pill: dark base, hover gets neon border glow + subtle scale.
Surface {
    id: root

    property string icon: ""
    property int iconSize: Dimensions.icon.medium
    property color iconColor: Colors.onSurfaceVariant

    property string text: ""
    property int textSize: Typography.size.labelMedium
    property int textWeight: Typography.weight.bold
    property color textColor: Colors.onSurface
    property int textMaxWidth: -1

    // Optional small glyph after the label, for state that qualifies the
    // value (the headset chip uses it to mark a cached charge).
    property string trailingIcon: ""
    property color trailingIconColor: Colors.onSurfaceVariant

    property int horizontalPadding: Dimensions.padding.chipHorizontal
    property int spacing: 6

    // Persistent accent state for a pill whose popup is open.
    property bool active: false

    readonly property bool hovered: _hover.hovered

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + horizontalPadding * 2
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // Neon border on hover, kept while the pill's popup is open.
    borderColor: hovered || active
        ? Colors.withAlpha(Colors.primary, 0.55)
        : Colors.withAlpha(Colors.outlineVariant, 0.18)

    Behavior on borderColor {
        ColorAnimation { duration: Motion.hover }
    }

    scale: hovered ? 1.04 : 1.0
    Behavior on scale {
        NumberAnimation { duration: Motion.scale; easing.type: Easing.OutCubic }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing

        Text {
            id: iconLabel
            visible: root.icon !== ""
            text: root.icon
            color: root.hovered ? Colors.primary : root.iconColor
            font.family: Typography.iconFont
            font.pixelSize: root.iconSize
            font.weight: Font.Normal
            Behavior on color { ColorAnimation { duration: Motion.hover } }
        }

        Text {
            id: textLabel
            visible: root.text !== ""
            text: root.text
            color: root.textColor
            font.family: Typography.barFont
            font.pixelSize: root.textSize
            font.weight: root.textWeight
            elide: Text.ElideRight
            width: root.textMaxWidth > 0 ? Math.min(implicitWidth, root.textMaxWidth) : implicitWidth
            Behavior on color { ColorAnimation { duration: Motion.color } }
        }

        Text {
            id: trailingIconLabel
            visible: root.trailingIcon !== ""
            text: root.trailingIcon
            color: root.hovered ? Colors.primary : root.trailingIconColor
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.small
            font.weight: Font.Normal
            Behavior on color { ColorAnimation { duration: Motion.hover } }
        }
    }

    HoverHandler { id: _hover }
}
