import QtQuick
import "../../../theme"

// Clipped single-line label that marquees only while the text overflows the
// viewport. Width changes come from Behaviors, so syncMarquee() is called per
// animation frame and must not restart an already running loop.
Item {
    id: root

    property string text: ""

    readonly property alias textWidth: textLabel.implicitWidth

    clip: true

    function syncMarquee() {
        const overflow = visible && textLabel.implicitWidth > root.width;

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

    Text {
        id: textLabel

        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Colors.onSurface
        font.family: Typography.barFont
        font.pixelSize: Typography.size.labelMedium
        font.weight: Typography.weight.bold
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
