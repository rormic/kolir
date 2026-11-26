pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../bar/components"
import "../theme"

// One notification card in the overlay stack. The notification server and
// the overlay window stay in Notification.qml.
//
// A card can carry a whole run of notifications from one app. The newest one
// is the card itself; the older ones sit behind it as a hint of a stack and
// expand in place when the count control is pressed. A run of one
// notification is the original card with no control and no layers.
Surface {
    id: root

    // Oldest-first notifications from one app; the last entry is the freshest.
    required property var group
    required property int index

    readonly property var latest: root.group.length > 0
        ? root.group[root.group.length - 1] : null
    readonly property int count: root.group.length
    readonly property bool grouped: root.count > 1
    // Expanded content is newest-first and capped, so a burst of twenty
    // messages cannot grow the card past the screen.
    readonly property int maxExpandedOthers: 4
    readonly property var others: {
        const list = [];
        for (let i = root.group.length - 2; i >= 0; i--)
            list.push(root.group[i]);
        return list;
    }
    readonly property var expandedOthers: root.others.slice(0, root.maxExpandedOthers)
    readonly property int hiddenExpanded:
        Math.max(0, root.others.length - root.maxExpandedOthers)
    property bool expanded: false

    readonly property bool isCritical: {
        for (let i = 0; i < root.group.length; i++) {
            if (root.group[i].urgency === NotificationUrgency.Critical)
                return true;
        }
        return false;
    }

    readonly property color fg: Colors.onSurface
    readonly property color accent: Colors.primary
    readonly property color critical: Colors.error
    readonly property color tint: root.isCritical ? root.critical : root.accent

    // Theme app icons follow the AppIcon rule: QIcon never upscales raster art,
    // so a 16 px request decodes the 16 px PNG. Ask for twice the slot instead
    // and let Image downscale a 32 px asset.
    readonly property int appIconPixels: Math.max(2, Math.round(16 * Screen.devicePixelRatio * 2))

    // 0 = folded, 1 = fully open. The older blocks live in a clipped box whose
    // height follows this value, so expanding and collapsing both animate.
    // Hiding the list and animating implicitHeight alone left an empty card
    // shrinking under the newest message.
    readonly property bool foldOpen: root.expanded && root.others.length > 0
    property real fold: 0

    // Keep the older blocks alive while the card closes, so the collapse
    // animates; a folded card builds nothing.
    readonly property bool foldActive: root.fold > 0.001

    // A clip edge sweeping over visible glyphs at 180 ms cuts several text
    // lines per frame, which reads as the text jumping. Collapsing therefore
    // fades the older blocks out first and only then shrinks the empty space;
    // the edge never crosses a readable line. The two halves still add up to
    // Motion.move, so the speed stays the same.
    property real foldFade: 0
    readonly property int foldFadeOutTime: Motion.durationShort1
    readonly property int foldCloseTime: Motion.move - root.foldFadeOutTime

    onFoldOpenChanged: {
        if (root.foldOpen) {
            foldCloseAnim.stop();
            foldFadeInAnim.restart();
            foldOpenAnim.restart();
        } else {
            foldOpenAnim.stop();
            if (root.others.length === 0) {
                foldCloseAnim.stop();
                root.fold = 0;
                root.foldFade = 0;
            } else if (root.fold > 0.001) {
                foldCloseAnim.restart();
            } else {
                root.foldFade = 0;
            }
        }
    }

    NumberAnimation {
        id: foldOpenAnim

        target: root
        property: "fold"
        to: 1
        duration: Motion.move
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.emphasizedDecelerateCurve
    }

    NumberAnimation {
        id: foldFadeInAnim

        target: root
        property: "foldFade"
        to: 1
        duration: Motion.fade
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.standardDecelerateCurve
    }

    SequentialAnimation {
        id: foldCloseAnim

        // The older text dims while the card still has its full height...
        NumberAnimation {
            target: root
            property: "foldFade"
            to: 0
            duration: root.foldFadeOutTime
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedAccelerateCurve
        }
        // ...and only the now empty space closes.
        NumberAnimation {
            target: root
            property: "fold"
            to: 0
            duration: root.foldCloseTime
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedAccelerateCurve
        }
    }

    implicitHeight: content.implicitHeight + 24 + foldArea.height

    radius: Dimensions.radius.large
    // Frosted like the file picker: the `notifications-no-anim` layer rule
    // blurs what is behind the card, so the fill has to stay translucent
    // enough to show it. A 0.96 fill would hide the effect completely.
    surfaceColor: hover.hovered
        ? Colors.withAlpha(Colors.surfaceContainerHigh, 0.88)
        : Colors.withAlpha(Colors.surfaceContainerLow, 0.80)
    borderWidth: 1
    borderColor: root.isCritical
        ? Colors.withAlpha(root.critical, 0.55)
        : hover.hovered
            ? Colors.withAlpha(root.accent, 0.65)
            : Colors.withAlpha(root.accent, 0.4)

    // Поява карточки з верхнього правого кута
    property real appear: 0
    // Закриття складається з двох фаз: картка гасне й трохи стискається, а
    // обгортка в Notification.qml після короткої паузи схлопує її висоту.
    // Лише після цього commitClose() прибирає рядки з моделі, тому
    // layer-surface не зникає посеред анімації.
    property real closeFade: 0
    property real closeProgress: 0
    property bool closing: false
    // 0 = dismiss(), 1 = expire()
    property int closeMode: 0
    // Чи натиснутий контрол лічильника стосу; поки так, картка не реагує на
    // клік, щоб один тап не закрив її разом із розгортанням.
    property bool countPressed: false
    // Група, яку закриває ця картка. Знімок робиться на старті закриття, щоб
    // повідомлення, яке прийшло під час анімації, не зникло разом з нею.
    property var closingGroup: []

    // The card only fades in and out. A scale animation would re-rasterise the
    // text at a different size on every frame, which reads as the font jumping
    // during the show/hide and stack animations.
    opacity: appear * (1 - closeFade)

    signal closeStarted

    function requestClose(mode) {
        if (closing)
            return;

        closeMode = mode;
        closing = true;
        root.closingGroup = root.group.slice();
        closeStarted();
        closeFadeAnim.start();
    }

    // Викликає обгортка після завершення схлопування висоти.
    function commitClose() {
        if (!closing)
            return;

        const members = root.closingGroup.length > 0 ? root.closingGroup : root.group;
        for (let i = 0; i < members.length; i++) {
            if (root.closeMode === 1)
                members[i].expire();
            else
                members[i].dismiss();
        }
    }

    SequentialAnimation {
        id: appearAnim

        PauseAnimation {
            duration: Math.max(0, Math.min((root.index >= 0 ? root.index : 0)
                * Motion.durationShort1, Motion.durationMedium2))
        }
        NumberAnimation {
            target: root
            property: "appear"
            to: 1
            duration: Motion.listEnter
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.emphasizedDecelerateCurve
        }
    }

    NumberAnimation {
        id: closeFadeAnim

        target: root
        property: "closeFade"
        from: 0
        to: 1
        duration: Motion.listExit
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.emphasizedAccelerateCurve
    }

    Component.onCompleted: appearAnim.start()

    // Нове повідомлення в групі має продовжити життя картки. Писати в
    // Timer.running напряму не можна: це знищило б його binding, тому
    // перезапуск іде через прапорець, який на мить зупиняє таймер.
    property bool timerHold: false

    // Автозакриття: критичні лишаються, поки не закриєш вручну.
    // expireTimeout — це вже мілісекунди з D-Bus, не секунди.
    // Поки група розгорнута, таймер стоїть: людина читає, а не змагається з
    // автозакриттям. Згортання запускає повний інтервал заново.
    Timer {
        id: autoClose

        running: !root.isCritical && !hover.hovered && !root.closing
            && !root.timerHold && !root.expanded
        interval: root.latest && root.latest.expireTimeout > 0
            ? root.latest.expireTimeout : 5000
        onTriggered: root.requestClose(1)
    }

    Timer {
        interval: 0
        running: root.timerHold
        onTriggered: root.timerHold = false
    }

    onCountChanged: {
        root.timerHold = true;
        if (root.count <= 1)
            root.expanded = false;
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    // Клік по картці закриває всю групу
    TapHandler {
        id: tap
        // Вкладений TapHandler лічильника отримує той самий клік. Поки він
        // натиснутий, картковий обробник вимкнений, інакше один клік і
        // розгортав, і закривав би картку.
        enabled: !root.countPressed
        onTapped: root.requestClose(0)
    }

    Column {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 6

        // Шапка: іконка застосунку + назва + лічильник групи
        RowLayout {
            width: parent.width
            spacing: 8

            Image {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter
                visible: status === Image.Ready
                source: {
                    const icon = root.latest
                        ? (root.latest.appIcon || root.group[0].appIcon) : "";
                    if (!icon)
                        return "";
                    return icon.startsWith("/")
                        ? icon
                        : Quickshell.iconPath(icon, "application-x-executable");
                }
                sourceSize: Qt.size(root.appIconPixels, root.appIconPixels)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            Text {
                Layout.fillWidth: true
                text: root.latest ? root.latest.appName : ""
                color: root.tint
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.medium
                elide: Text.ElideRight
            }

            // Замість бейджа — тихий контрол «N ⌄»: цифра і шеврон, які
            // підсвічуються лише під курсором і розгортають стос.
            Item {
                id: countControl

                Layout.alignment: Qt.AlignVCenter
                visible: root.grouped
                implicitWidth: countRow.implicitWidth + 14
                implicitHeight: 20

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: countHover.hovered
                        ? Colors.stateLayer(Colors.onSurface, 0.08)
                        : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.hover
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.standardDecelerateCurve
                        }
                    }
                }

                Row {
                    id: countRow

                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.count
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        font.weight: Typography.weight.medium
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.expanded ? Icons.chevronUp : Icons.chevronDown
                        color: Colors.onSurfaceVariant
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.small
                    }
                }

                HoverHandler {
                    id: countHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: countTap
                    onPressedChanged: root.countPressed = countTap.pressed
                    onTapped: root.expanded = !root.expanded
                }
            }
        }

        // Найсвіжіше повідомлення
        Text {
            width: parent.width
            visible: text !== ""
            text: root.latest ? root.latest.summary : ""
            color: root.fg
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: Typography.weight.bold
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.latest ? root.latest.body : ""
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        // Кнопки дій у стилі бару (дії найсвіжішого повідомлення)
        Row {
            spacing: 6
            visible: root.latest !== null && root.latest.actions.length > 0

            Repeater {
                model: root.latest !== null ? root.latest.actions : []

                delegate: Pill {
                    id: actionPill

                    required property var modelData

                    text: modelData.text
                    textSize: Typography.size.labelSmall
                    textWeight: Typography.weight.medium
                    horizontalPadding: Dimensions.padding.chipHorizontal

                    TapHandler {
                        onTapped: actionPill.modelData.invoke()
                    }
                }
            }
        }

        // Решта повідомлень групи: повні блоки в тому ж ритмі, що й картка.
        // Вони живуть поза цим стовпцем, у clip-боксі під ним (див. foldArea),
        // щоб згортання не лишало порожньої картки.
    }

    // The folded stack: clipped so the card reveals it top-down, and driven by
    // `fold` so closing runs the same motion backwards. The 6 px gap above the
    // first block lives inside the clip (foldContent.y), not in an animated
    // margin, so the blocks keep one y for the whole motion.
    Item {
        id: foldArea

        anchors {
            left: parent.left
            right: parent.right
            top: content.bottom
            leftMargin: 12
            rightMargin: 12
        }
        // The 6 px gap above the first older block is part of the clipped box,
        // not an animated margin: the blocks then keep one fixed y for the
        // whole motion and only the edge moves, so the text cannot drift.
        height: (foldContent.implicitHeight + 6) * root.fold
        opacity: root.foldFade
        clip: true

        Column {
            id: foldContent

            y: 6
            width: parent.width
            spacing: 6

            Repeater {
                model: root.others.length > 0 && root.foldActive
                    ? root.expandedOthers
                    : []

                delegate: Column {
                    id: olderBlock

                    required property var modelData

                    width: foldContent.width
                    spacing: 6

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.22)
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: olderBlock.modelData.summary
                        color: root.fg
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.titleSmall
                        font.weight: Typography.weight.bold
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: olderBlock.modelData.body
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                width: foldContent.width
                visible: root.hiddenExpanded > 0
                text: "+" + root.hiddenExpanded + " more"
                color: Colors.onSurfaceVariant
                opacity: 0.7
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }
        }
    }
}
