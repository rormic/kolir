import QtQuick
import "../../../theme"

// "LIVE" pill shared by the compact now-playing island and its expanded card.
//
// A broadcast needs a stronger marker than a bare dot: the pill names the
// state, and its dot pulses only while the stream is really playing. The pulse
// animates a private phase instead of `opacity`, because a stopped property
// animation would leave the dot frozen at a random brightness instead of the
// dim paused state.
Rectangle {
    id: root

    property bool playing: false
    // Compact pill for the 24px bar strip; the expanded card uses the roomier
    // variant with the same colors.
    property bool compact: true

    readonly property int pillHeight: compact ? 15 : 20
    readonly property int dotSize: compact ? 4 : 6
    readonly property int labelSize: compact ? 8 : 10
    readonly property int horizontalPadding: compact ? 5 : 8
    readonly property int dotSpacing: compact ? 3 : 5

    implicitWidth: content.width + horizontalPadding * 2
    implicitHeight: pillHeight
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Colors.errorContainer
    border.width: 1
    border.color: Colors.withAlpha(Colors.error, 0.35)

    property real phase: 0

    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 1400
        loops: Animation.Infinite
        running: root.playing && root.visible
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: root.dotSpacing

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.dotSize
            height: root.dotSize
            radius: root.dotSize / 2
            color: Colors.error
            opacity: root.playing
                ? 0.3 + 0.7 * (0.5 + 0.5 * Math.cos(root.phase))
                : 0.45
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "LIVE"
            color: Colors.onErrorContainer
            font.family: Typography.barFont
            font.pixelSize: root.labelSize
            font.weight: Typography.weight.bold
            font.letterSpacing: 0.8
        }
    }
}
