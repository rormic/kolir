import QtQuick
import "../theme"

// Keycap-styled label used by the shortcut sheet: the key chips in the rows
// and the small Esc/SUPER+D hints in the footer.
Rectangle {
    id: root

    property string label: ""
    property int labelSize: Typography.size.labelMedium
    property int horizontalPadding: 9
    // Caps the chip so a long gesture name cannot push the description column.
    property real maxWidth: -1

    readonly property real naturalWidth: Math.max(32,
        metrics.advanceWidth + root.horizontalPadding * 2)

    implicitWidth: root.maxWidth > 0
        ? Math.min(root.naturalWidth, root.maxWidth)
        : root.naturalWidth
    implicitHeight: 24
    radius: Dimensions.radius.small
    color: Colors.withAlpha(Colors.surfaceContainerHighest, 0.75)
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.28)

    TextMetrics {
        id: metrics

        font.family: Typography.barFont
        font.pixelSize: root.labelSize
        font.weight: Typography.weight.bold
        text: root.label
    }

    Text {
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        text: root.label
        color: Colors.primary
        font.family: Typography.barFont
        font.pixelSize: root.labelSize
        font.weight: Typography.weight.bold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
