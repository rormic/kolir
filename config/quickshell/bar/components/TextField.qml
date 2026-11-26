import QtQuick
import "../../theme"

// Single-line text field shared by the embedded sheets. The calendar event
// form is the first user; the styling matches the file picker's path field so
// inputs look the same everywhere inside the bar surface.
//
// The owning form decides what submission and cancellation mean through the
// `accepted`/`canceled` signals; this only reports them and paints the focus
// and validation states.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property bool invalid: false

    signal accepted()
    signal canceled()

    implicitHeight: 32
    radius: Dimensions.radius.small
    color: Colors.surfaceContainerLowest
    border.width: 1
    border.color: root.invalid
        ? Colors.error
        : input.activeFocus
            ? Colors.withAlpha(Colors.primary, 0.7)
            : Colors.withAlpha(Colors.outlineVariant, 0.4)

    Behavior on border.color {
        ColorAnimation {
            duration: Motion.hover
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.standardDecelerateCurve
        }
    }

    function forceFocus() {
        input.forceActiveFocus();
        input.selectAll();
    }

    TextInput {
        id: input

        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        verticalAlignment: TextInput.AlignVCenter
        color: Colors.onSurface
        selectionColor: Colors.withAlpha(Colors.primary, 0.35)
        selectedTextColor: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelMedium
        clip: true
        selectByMouse: true
        activeFocusOnTab: true

        Keys.onReturnPressed: event => {
            root.accepted();
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            root.accepted();
            event.accepted = true;
        }
        Keys.onEscapePressed: event => {
            root.canceled();
            event.accepted = true;
        }

        // TextInput never sets a cursor shape of its own (Qt only paints the
        // caret), so hovering would keep the arrow. The handler shows the
        // I-beam without touching click or selection delivery.
        HoverHandler {
            cursorShape: Qt.IBeamCursor
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.placeholder !== "" && !input.text && !input.activeFocus
            text: root.placeholder
            color: Colors.onSurfaceVariant
            font: input.font
        }
    }
}
