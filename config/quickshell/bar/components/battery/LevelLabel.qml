import QtQuick
import "../../../theme"

// One percentage string for the battery gauge: digits plus an optional
// charging bolt.
//
// The owning chip paints two instances of this label, one clipped to the
// level fill and one to the empty track, so the digits change colour exactly
// at the gauge's edge. Each instance therefore lays its content out against
// the whole gauge width and is then clipped by the caller; it must never
// centre its content inside the clip region.
Item {
    id: root

    property real gaugeWidth: 0
    property real gaugeHeight: 0
    property string value: ""
    property bool showBolt: false
    property color foreground: Colors.onSurface

    width: gaugeWidth
    height: gaugeHeight

    Row {
        anchors.centerIn: parent
        spacing: root.showBolt ? 1 : 0

        Text {
            id: numberLabel

            text: root.value
            color: root.foreground
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
            // The digits must not shiver while the level changes.
            font.features: ({ "tnum": 1 })
        }

        // The bolt glyph uses another font, so it is centred against the
        // number's line box instead of sharing its baseline.
        Item {
            width: root.showBolt ? boltLabel.implicitWidth : 0
            height: numberLabel.implicitHeight

            Text {
                id: boltLabel

                anchors.centerIn: parent
                visible: root.showBolt
                text: Icons.bolt
                color: root.foreground
                font.family: Typography.iconFont
                font.pixelSize: 10
                font.weight: Font.Normal
            }
        }
    }
}
