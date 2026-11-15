import QtQuick
import "../../theme"

// Compact Material 3 pill: icon + label inside a fully rounded tonal surface.
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

    property int horizontalPadding: Dimensions.padding.chipHorizontal
    property int spacing: 6

    property alias iconItem: iconLabel
    property alias textItem: textLabel

    implicitHeight: Dimensions.control.height
    implicitWidth: row.implicitWidth + horizontalPadding * 2
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing

        Text {
            id: iconLabel
            visible: root.icon !== ""
            text: root.icon
            color: root.iconColor
            font.family: Typography.iconFont
            font.pixelSize: root.iconSize
            font.weight: Font.Normal

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
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

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
        }
    }
}
