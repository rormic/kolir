import QtQuick
import QtQuick.Layouts
import "../../theme"

// Control pill that turns into its sheet's header.
//
// The sheets are owned by Bar and live in the bar surface, so a chip only
// reports clicks through `activated`. While its sheet is open the chip stops
// being a chip: it stretches over the sheet's width and becomes its header, so
// the bar and the sheet read as one surface instead of a small pill above a
// separate title block.
//
// Bar supplies the geometry in bar coordinates: `barX` (this chip's left edge),
// `headerX`/`headerWidth` (the sheet body edge and the run to the physical
// screen edge) and `headerInset` (the sheet's content inset, so the title lines
// up with its cards).
Pill {
    id: root

    signal activated()

    // Called with +1 / -1 when the wheel turns over the chip or its header.
    property var adjust: null

    // Bound by Bar to the embedded popup's modal state.
    property bool popupActive: false

    // Header content, supplied by the chip that owns a sheet.
    property string headerIcon: ""
    property color headerIconColor: Colors.primary
    property string headerTitle: ""
    property string headerStatus: ""
    property color headerStatusColor: Colors.onSurfaceVariant

    // Sheet geometry and open progress.
    property real headerReveal: 0
    property real barX: 0
    property real headerX: 0
    property real headerWidth: 0
    property real headerInset: 0

    // Another sheet opened while this one is still collapsing: the strip
    // belongs to the new header, so this band steps aside at once instead of
    // overlapping it with a second capsule and a second outline.
    property bool headerBlocked: false

    // Progress line along the chip's bottom edge.
    property real progressValue: 0
    property color progressColor: Colors.primary
    property color progressTrackColor: Colors.withAlpha(Colors.surfaceContainerHighest, 0.7)

    // False removes the pointer affordances; a chip whose backend is missing is
    // hidden, yet its sheet can still be opened over IPC.
    property bool interactive: true

    readonly property bool headerMode: headerReveal > 0.001
    // Width leads the sheet (the same curve EmbeddedSheet uses for its reveal)
    // so the header reaches the panel edge before the panel finishes dropping.
    readonly property real stretch: Math.min(1, Math.max(0, headerReveal) * 1.35)
    // The title only has room once the band is wide: it fades in after the
    // first half of the stretch instead of riding a narrow pill.
    readonly property real headerContent: Math.max(0, Math.min(1,
        (headerReveal - 0.5) / 0.5))
    // The chip's face fades out exactly while the header text fades in, so the
    // level never pops out of the pill when the sheet takes it over.
    readonly property real faceOpacity: 1 - headerContent
    readonly property bool bandVisible: root.headerMode && !root.headerBlocked

    // The night-light tooltip hangs below the pill, so the surface itself must
    // not clip its children (the stretched header reaches past it too).
    clip: false
    active: root.popupActive
    // When the band steps aside the chip has to look like a chip again at once,
    // so its face comes back with it.
    contentOpacity: root.bandVisible ? root.faceOpacity : 1
    // The stretched header covers the neighbouring chips in the control row.
    z: root.headerMode ? 10 : 0
    // A header does not bounce: the hover scale is a chip affordance only.
    scale: hovered && !root.headerMode ? 1.04 : 1.0

    function stepWheel(delta) {
        if (!root.adjust || !root.interactive)
            return;

        if (delta > 0)
            root.adjust(1);
        else if (delta < 0)
            root.adjust(-1);
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
        onWheel: wheel => root.stepWheel(wheel.angleDelta.y)
    }

    // Material 3 linear progress indicator along the bottom edge.
    ProgressIndicator {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 6
            rightMargin: 6
            bottomMargin: 2
        }
        height: implicitHeight
        value: root.progressValue
        indicatorColor: root.progressColor
        trackColor: root.progressTrackColor
        opacity: root.bandVisible ? root.faceOpacity : 1
    }

    // Stretched pill that becomes the sheet's header. It grows out of the
    // chip's own rect and stays a capsule the whole way, so its rounded right
    // end just touches the physical screen edge. The corners the cap reveals
    // are the bar strip and the sheet body, which share `surfaceContainerLow`,
    // so the rounding never shows a gap.
    Item {
        id: headerBand

        readonly property real bandHeight: root.height
            + (Dimensions.bar.height - root.height) * root.stretch

        x: (root.headerX - root.barX) * root.stretch
        y: (root.height - bandHeight) / 2
        width: root.width + (root.headerWidth - root.width) * root.stretch
        height: bandHeight
        visible: root.bandVisible
        clip: false
        // Behind the chip's own face: the value and its progress line stay put
        // on the widening band and crossfade into the header instead of being
        // cut off by it. The whole chip is lifted above the other controls, so
        // the band still covers the neighbouring chips.
        z: -1

        Rectangle {
            anchors.fill: parent
            color: root.surfaceColor
            border.width: root.borderWidth
            border.color: root.borderColor
            topLeftRadius: parent.height / 2
            bottomLeftRadius: parent.height / 2
            topRightRadius: parent.height / 2
            bottomRightRadius: parent.height / 2

            Behavior on color {
                ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
            }

            Behavior on border.color {
                ColorAnimation { duration: Motion.color; easing.type: Motion.themeEasing }
            }
        }

        RowLayout {
            anchors {
                fill: parent
                // The sheet's content inset: the title lines up with the cards
                // instead of hugging the pill's rounded end.
                leftMargin: root.headerInset
                rightMargin: 12
            }
            spacing: 8
            opacity: root.headerContent

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.headerIcon !== ""
                text: root.headerIcon
                color: root.headerIconColor
                font.family: Typography.iconFont
                font.pixelSize: Typography.size.bodyLarge
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.headerTitle
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.semibold
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.headerStatus
                color: root.headerStatusColor
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }

            // The stretched band covers the chip, so the level it used to show
            // stays readable on the header's right end.
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.text
                color: root.textColor
                font.family: Typography.barFont
                font.pixelSize: root.textSize
                font.weight: root.textWeight
            }
        }

        // The band is the chip, so it keeps the chip's contract: click toggles
        // the sheet, the wheel still moves the level.
        MouseArea {
            anchors.fill: parent
            enabled: root.interactive
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
            onWheel: wheel => root.stepWheel(wheel.angleDelta.y)
        }
    }
}
