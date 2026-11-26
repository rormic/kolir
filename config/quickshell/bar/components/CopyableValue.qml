import QtQuick
import Quickshell.Io
import "../../theme"

// Read-only detail value that copies its whole text to the clipboard on click.
// The settings sheet has no text selection, so the copy glyph is the
// affordance: it fades in on hover and turns into a check for a moment after
// the click. `wl-copy` is used instead of Quickshell's clipboard binding so the
// copy still lands when the bar surface does not own the keyboard focus.
Text {
    id: root

    // Raw value; an empty value renders the placeholder dash and is not
    // copyable, so a missing detail never puts "—" on the clipboard.
    property string value: ""
    property bool wrap: false

    readonly property bool copyable: root.value !== ""
    property bool hovered: false
    property bool copied: false

    text: root.copyable ? root.value : "—"
    color: Colors.onSurface
    font.family: Typography.barFont
    font.pixelSize: Typography.size.labelSmall
    wrapMode: root.wrap ? Text.Wrap : Text.NoWrap
    elide: root.wrap ? Text.ElideNone : Text.ElideRight
    // Keeps the text clear of the copy glyph drawn at the right edge.
    rightPadding: 16

    Process {
        id: copyProc
        running: false
    }

    Timer {
        id: feedbackTimer
        interval: 1400
        onTriggered: root.copied = false
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.copyable
        cursorShape: root.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: root.hovered = containsMouse
        onClicked: {
            copyProc.command = ["wl-copy", root.value];
            copyProc.running = true;
            root.copied = true;
            feedbackTimer.restart();
        }
    }

    Text {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        text: root.copied ? Icons.check : Icons.contentCopy
        color: root.copied ? Colors.primary : Colors.onSurfaceVariant
        font.family: Typography.iconFont
        font.pixelSize: Dimensions.icon.small
        opacity: root.copyable && (root.hovered || root.copied) ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.hover
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }
}
