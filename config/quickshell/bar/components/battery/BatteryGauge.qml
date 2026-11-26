import QtQuick
import "../../../theme"
import ".."

// Battery chip face: a battery silhouette whose fill is the charge level and
// whose percentage is drawn inside it.
//
// The digits are painted twice and clipped at the fill edge, so the part over
// the bright fill stays dark and the part over the empty track stays light:
// the number reads on both backgrounds instead of sitting on one flat colour.
// The charging bolt rides along with the label; a missing battery replaces the
// number with the alert glyph.
//
// This component is purely visual: Battery.qml owns the BatteryService
// mapping, the charge bloom and the scale pulse. The plain properties keep the
// gauge previewable with fixed values.
Item {
    id: root

    signal activated()

    property int level: 0
    property bool present: true
    property bool charging: false
    property bool low: false
    // Persistent accent while the battery sheet is open.
    property bool active: false

    // Gauge metrics. The body is almost the whole chip: a battery reads as a
    // charge gauge, not as an icon plus a separate label. Wide enough for
    // "100%" plus the charging bolt without crowding the rounded caps.
    readonly property int bodyWidth: 48
    readonly property int bodyRadius: 8
    readonly property int nubWidth: 2
    readonly property int nubHeight: 9
    readonly property int nubGap: 2
    // A 1% level would be a sub-pixel line. Once there is any charge at all,
    // keep a visible sliver so the gauge never looks empty while discharging.
    readonly property int minimumFill: 3

    readonly property bool missing: !root.present
    readonly property bool hovered: _hover.hovered

    readonly property real fillWidth: root.missing
        ? 0
        : Math.max(root.level > 0 ? root.minimumFill : 0,
            root.bodyWidth * root.level / 100)

    readonly property color fillColor: root.low
        ? Colors.error
        : root.charging
            ? Colors.primary
            : Colors.onSurface

    readonly property color fillTextColor: root.low
        ? Colors.errorContainer
        : root.charging
            ? Colors.onPrimary
            : Colors.surfaceContainerLowest

    readonly property color trackTextColor: root.low
        ? Colors.error
        : Colors.onSurface

    readonly property color borderColor: root.missing
        ? Colors.withAlpha(Colors.error, 0.45)
        : root.hovered || root.active
            ? Colors.withAlpha(Colors.primary, 0.55)
            : Colors.withAlpha(Colors.outlineVariant, 0.18)

    implicitWidth: root.bodyWidth + root.nubGap + root.nubWidth
    implicitHeight: Dimensions.control.height
    width: implicitWidth
    height: implicitHeight

    scale: root.hovered ? 1.04 : 1.0

    // Small interactive control scale: the M3 fast spatial spring.
    Behavior on scale {
        SpringAnimation {
            spring: Motion.spatialSpringFast
            damping: Motion.spatialSpringFastDamping
            epsilon: Motion.springScaleEpsilon
        }
    }

    Surface {
        id: body

        width: root.bodyWidth
        height: parent.height
        radius: root.bodyRadius
        surfaceColor: Colors.surfaceContainerHigh
        borderColor: root.borderColor

        Behavior on borderColor {
            ColorAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }

        // The level: a full-size capsule revealed by a rectangular clip. The
        // filled part keeps the body's rounded left cap and ends in a straight
        // edge at the current level, while a full charge still shows the
        // capsule's rounded right end.
        Item {
            id: fill

            width: root.fillWidth
            height: parent.height
            clip: true

            Behavior on width {
                NumberAnimation {
                    duration: Motion.move
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }

            Rectangle {
                width: body.width
                height: body.height
                radius: root.bodyRadius
                color: root.fillColor
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.missing
            text: Icons.batteryMissing
            color: Colors.error
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.large
            font.weight: Font.Normal
        }

        // Dark half of the number: the part that sits over the fill.
        Item {
            id: fillClip

            width: fill.width
            height: parent.height
            clip: true
            visible: !root.missing

            LevelLabel {
                gaugeWidth: body.width
                gaugeHeight: body.height
                value: root.level + "%"
                showBolt: root.charging
                foreground: root.fillTextColor
            }
        }

        // Light half of the number: the part that sits over the track. The
        // label is shifted left by the fill's width so both copies stay
        // aligned and the colour changes exactly at the edge.
        Item {
            id: trackClip

            x: fill.width
            width: body.width - fill.width
            height: body.height
            clip: true
            visible: !root.missing

            LevelLabel {
                x: -fill.width
                gaugeWidth: body.width
                gaugeHeight: body.height
                value: root.level + "%"
                showBolt: root.charging
                foreground: root.trackTextColor
            }
        }
    }

    // The battery's positive terminal: a short nub on the right edge, outside
    // the body so it survives at any fill level. It carries the charge state
    // as an accent so the cue does not depend on the bolt alone.
    Rectangle {
        id: nub

        anchors.left: body.right
        anchors.leftMargin: root.nubGap
        anchors.verticalCenter: body.verticalCenter
        width: root.nubWidth
        height: root.nubHeight
        radius: width / 2
        color: root.low
            ? Colors.error
            : root.charging
                ? Colors.primary
                : Colors.withAlpha(Colors.onSurfaceVariant, 0.4)
    }

    HoverHandler { id: _hover }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.missing
        ? "Battery missing"
        : "Battery " + root.level + "%"
}
