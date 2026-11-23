import QtQuick
import "../../../theme"

// Clipped single-line label that marquees only while the text overflows the
// viewport. Width changes come from Behaviors, so syncMarquee() is called per
// animation frame and must not restart an already running loop.
Item {
    id: root

    property string text: ""
    // Optional style overrides; the defaults match the now-playing usage, so
    // existing callers keep their exact look.
    property color textColor: Colors.onSurface
    property int textSize: Typography.size.labelMedium
    property int textWeight: Typography.weight.bold
    // Owner-controlled gate: the loop must stop while the panel that hosts the
    // text is hidden. Items stay in the tree when a sheet closes, so their own
    // `visible` is still true. Defaults to true for callers that do not set it.
    property bool active: true

    readonly property alias textWidth: textLabel.implicitWidth

    clip: true

    function syncMarquee() {
        const overflow = root.active && visible && textLabel.implicitWidth > root.width;

        if (overflow) {
            if (!marquee.running)
                marquee.restart();
        } else {
            marquee.stop();
            textLabel.x = 0;
        }
    }

    onTextChanged: {
        textLabel.x = 0;
        marquee.stop();
        syncMarquee();
    }

    onVisibleChanged: syncMarquee()
    onWidthChanged: syncMarquee()
    onActiveChanged: syncMarquee()

    Text {
        id: textLabel

        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.textColor
        font.family: Typography.barFont
        font.pixelSize: root.textSize
        font.weight: root.textWeight
    }

    // Marquee: rest, scroll through the title, rest, slide back.
    SequentialAnimation {
        id: marquee

        loops: Animation.Infinite

        PauseAnimation { duration: 2000 }

        NumberAnimation {
            target: textLabel
            property: "x"
            from: 0
            to: root.width - textLabel.implicitWidth
            duration: Math.max(2500, (textLabel.implicitWidth - root.width) * 55)
            easing.type: Easing.InOutSine
        }

        PauseAnimation { duration: 2000 }

        NumberAnimation {
            target: textLabel
            property: "x"
            from: root.width - textLabel.implicitWidth
            to: 0
            duration: 700
            easing.type: Easing.InQuad
        }
    }

    Component.onCompleted: syncMarquee()
}
