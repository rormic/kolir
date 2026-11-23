import QtQuick
import QtQuick.Layouts
import "../../theme"

// Title block shared by the embedded sheets: a bold title with an optional
// status line. The sheet owns the surrounding layout and height.
ColumnLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    property color subtitleColor: Colors.onSurfaceVariant

    spacing: 2

    Text {
        Layout.fillWidth: true
        text: root.title
        color: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.titleLarge
        font.weight: Typography.weight.bold
        elide: Text.ElideRight
    }

    Text {
        Layout.fillWidth: true
        text: root.subtitle
        color: root.subtitleColor
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelSmall
        elide: Text.ElideRight
    }
}
