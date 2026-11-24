import QtQuick
import QtQuick.Layouts
import "../bar/components"
import "../services"
import "../theme"

// Screen frame mode card at the bottom of the Appearance page. Every entry in
// FrameService.styles becomes one visual preview, so adding another frame mode
// needs no change here. The card header names the hovered or selected mode;
// the tile itself is the control.
Rectangle {
    id: root

    property string hoveredStyle: ""

    implicitHeight: content.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    ColumnLayout {
        id: content

        anchors {
            fill: parent
            margins: 12
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                radius: Dimensions.radius.small + 2
                color: Colors.surfaceContainerHighest

                Text {
                    anchors.centerIn: parent
                    text: Icons.cropFree
                    color: Colors.onSurfaceVariant
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Screen frame"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.bodyMedium
                    font.weight: Typography.weight.medium
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hoveredStyle !== ""
                        ? FrameService.labelFor(root.hoveredStyle) + " · "
                            + FrameService.hintFor(root.hoveredStyle)
                        : "Choose how windows meet the screen edge"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: FrameService.styles

                delegate: FramePreview {
                    id: previewTile

                    required property var modelData

                    Layout.fillWidth: true
                    mode: previewTile.modelData.value
                    selected: FrameService.style === previewTile.modelData.value
                    onActivated: FrameService.setStyle(previewTile.modelData.value)
                    onHoveredChanged: {
                        if (previewTile.hovered) {
                            root.hoveredStyle = previewTile.modelData.value;
                        } else if (root.hoveredStyle === previewTile.modelData.value) {
                            root.hoveredStyle = "";
                        }
                    }
                }
            }
        }
    }
}
