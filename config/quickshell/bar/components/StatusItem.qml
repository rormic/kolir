import QtQuick
import "../../theme"

// Flat status readout: icon + optional label drawn directly on the bar strip.
//
// The bar has one visual contract: a filled pill or a hoverable icon opens a
// menu or performs an action, while a StatusItem is information drawn flat on
// the strip. It has no container and no hover scale, so a pass over the bar
// cannot mistake a headset percentage for a broken button. A status may still
// carry a direct action that matches its value (refresh the headset reading,
// stop a recording); that action is signalled by the alert itself or a trailing
// glyph, never by a pill and never by opening a sheet.
Item {
    id: root

    property string icon: ""
    property int iconSize: Dimensions.icon.medium
    property color iconColor: Colors.onSurfaceVariant

    // Optional context before the main value. The headset status uses it for
    // the device name; it elides first so the percentage stays readable.
    property string leadingText: ""
    property int leadingTextMaxWidth: -1
    property color leadingTextColor: Colors.onSurfaceVariant

    property string text: ""
    property int textSize: Typography.size.labelMedium
    property int textWeight: Typography.weight.medium
    property color textColor: Colors.onSurfaceVariant
    // Numeric values (a charge, a countdown) must not jitter as they tick.
    property bool tabular: true

    property string trailingIcon: ""
    property int trailingIconSize: Dimensions.icon.small
    property color trailingIconColor: Colors.onSurfaceVariant

    property int spacing: 4
    property int horizontalPadding: 2

    readonly property alias iconItem: iconLabel
    readonly property alias trailingIconItem: trailingIconLabel

    implicitWidth: row.implicitWidth + horizontalPadding * 2
    implicitHeight: Dimensions.control.height

    Row {
        id: row

        anchors.centerIn: parent
        spacing: root.spacing

        Text {
            id: iconLabel

            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            color: root.iconColor
            font.family: Typography.iconFont
            font.pixelSize: root.iconSize
            font.weight: Font.Normal
        }

        Text {
            id: leadingTextLabel

            anchors.verticalCenter: parent.verticalCenter
            visible: root.leadingText !== ""
            text: root.leadingText
            textFormat: Text.PlainText
            color: root.leadingTextColor
            font.family: Typography.barFont
            font.pixelSize: root.textSize
            font.weight: Typography.weight.regular
            elide: Text.ElideRight
            width: root.leadingTextMaxWidth > 0
                ? Math.min(implicitWidth, root.leadingTextMaxWidth)
                : implicitWidth
        }

        Text {
            id: textLabel

            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.textColor
            font.family: Typography.barFont
            font.pixelSize: root.textSize
            font.weight: root.textWeight
            font.features: root.tabular ? ({ "tnum": 1 }) : ({})
        }

        Text {
            id: trailingIconLabel

            anchors.verticalCenter: parent.verticalCenter
            visible: root.trailingIcon !== ""
            text: root.trailingIcon
            color: root.trailingIconColor
            font.family: Typography.iconFont
            font.pixelSize: root.trailingIconSize
            font.weight: Font.Normal
        }
    }
}
