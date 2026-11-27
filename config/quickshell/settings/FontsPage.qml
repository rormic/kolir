pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../bar/components"

// Desktop font selection: one interface family (bar and launcher) and one
// terminal family (Foot). Obsidian follows the two through a generated CSS
// snippet. The choice lives in FontService; this page only renders it and
// asks for the installed families. The lock screen stays on Google Sans Flex.
Item {
    id: root

    signal back()

    property int topInset: 0
    // Which picker is open: "" (closed), "interface" or "terminal".
    property string pickerTarget: ""
    property string query: ""

    readonly property bool pickingTerminal: root.pickerTarget === "terminal"
    readonly property string pickerTitle: root.pickingTerminal
        ? "Terminal font"
        : "Interface font"
    readonly property string pickerCurrent: root.pickingTerminal
        ? FontService.resolvedTerminalFont
        : FontService.resolvedInterfaceFont

    readonly property var filteredFonts: {
        const search = root.query.trim().toLowerCase();
        const mono = root.pickingTerminal;
        const current = root.pickerCurrent;
        const result = [];

        for (let i = 0; i < FontService.fonts.length; i++) {
            const font = FontService.fonts[i];
            if (mono && !font.mono && font.family !== current)
                continue;
            if (search !== "" && font.family.toLowerCase().indexOf(search) < 0)
                continue;

            result.push(font);
            if (result.length >= 300)
                break;
        }

        return result;
    }

    readonly property string obsidianStatus: {
        if (!FontService.obsidianFollows)
            return "Off — Obsidian keeps its own fonts";
        if (FontService.obsidianError !== "")
            return FontService.obsidianError;
        if (FontService.applying)
            return "Updating snippet…";
        if (FontService.obsidianVault !== "")
            return "Enabled in " + FontService.obsidianVault;
        return "Looking for a vault…";
    }

    readonly property bool obsidianFailed: FontService.obsidianFollows
        && FontService.obsidianError !== ""

    implicitWidth: 380
    // Mirrors `fontsHeight` in SettingsMenu.qml. The font list scrolls inside
    // the page, so the resting cards only need this much room.
    implicitHeight: 560

    function openPicker(target) {
        root.pickerTarget = target;
        root.query = "";
        flick.contentY = 0;
        FontService.ensureFonts(false);
        pickerSearch.forceFocus();
    }

    function closePicker() {
        root.pickerTarget = "";
        root.query = "";
    }

    function choose(family) {
        if (root.pickingTerminal)
            FontService.setTerminalFont(family);
        else
            FontService.setInterfaceFont(family);
        root.closePicker();
    }

    function resetPicker() {
        if (root.pickingTerminal)
            FontService.resetTerminalFont();
        else
            FontService.resetInterfaceFont();
        root.closePicker();
    }

    onVisibleChanged: {
        if (root.visible) {
            FontService.ensureFonts(false);
        } else {
            root.pickerTarget = "";
            root.query = "";
        }
    }

    Component.onCompleted: {
        if (root.visible)
            FontService.ensureFonts(false);
    }

    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Fonts"
        onBack: root.back()
    }

    Flickable {
        id: flick

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 14
        }
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The font list is its own flickable; leave the wheel to it while the
        // picker is open so one gesture never scrolls both.
        interactive: root.pickerTarget === ""

        ColumnLayout {
            id: body

            width: flick.width
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "The interface font is used by the bar and launcher. The "
                    + "terminal font is used by new Foot windows. Obsidian "
                    + "follows both through a CSS snippet. The lock screen keeps "
                    + "its Google Sans Flex clock."
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }

            // ── Font picker ──────────────────────────────────────────────
            Rectangle {
                id: pickerCard

                Layout.fillWidth: true
                implicitHeight: pickerColumn.implicitHeight + 24
                visible: root.pickerTarget !== ""
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.primary, 0.35)

                ColumnLayout {
                    id: pickerColumn

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.pickerTitle
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }

                        ActionChip {
                            label: "Close"
                            onClicked: root.closePicker()
                        }
                    }

                    TextField {
                        id: pickerSearch

                        Layout.fillWidth: true
                        placeholder: "Search fonts…"
                        onTextChanged: root.query = text
                        onCanceled: root.closePicker()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: FontService.fontsLoading
                                ? "Reading installed fonts…"
                                : FontService.fontsError !== ""
                                    ? FontService.fontsError
                                    : root.filteredFonts.length
                                        + (root.filteredFonts.length === 1
                                            ? " font" : " fonts")
                            color: FontService.fontsError !== ""
                                ? Colors.error
                                : Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }

                        ActionChip {
                            label: root.pickingTerminal
                                ? "Default (Google Sans Code NF)"
                                : "Default (Google Sans)"
                            onClicked: root.resetPicker()
                        }
                    }

                    ListView {
                        id: fontList

                        Layout.fillWidth: true
                        Layout.preferredHeight: 224
                        clip: true
                        model: root.filteredFonts
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2

                        delegate: Rectangle {
                            id: fontRow

                            required property var modelData

                            readonly property bool selected: modelData.family
                                === root.pickerCurrent
                            readonly property bool hovered: rowMouse.containsMouse

                            width: fontList.width
                            height: 38
                            radius: Dimensions.radius.small
                            color: fontRow.selected
                                ? Colors.primaryContainer
                                : fontRow.hovered
                                    ? Colors.withAlpha(Colors.primary, 0.12)
                                    : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.fade
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Motion.standardDecelerateCurve
                                }
                            }

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: fontRow.modelData.family
                                    color: fontRow.selected
                                        ? Colors.onPrimaryContainer
                                        : Colors.onSurface
                                    font.family: fontRow.modelData.family
                                    font.pixelSize: Typography.size.bodyMedium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: fontRow.modelData.mono
                                    text: "mono"
                                    color: fontRow.selected
                                        ? Colors.onPrimaryContainer
                                        : Colors.onSurfaceVariant
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelSmall
                                }

                                Text {
                                    visible: fontRow.selected
                                    text: Icons.check
                                    color: Colors.onPrimaryContainer
                                    font.family: Typography.iconFont
                                    font.pixelSize: Dimensions.icon.small
                                }
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.choose(fontRow.modelData.family)
                            }
                        }
                    }
                }
            }

            // ── Interface font ───────────────────────────────────────────
            FontCard {
                Layout.fillWidth: true
                icon: Icons.fontDownload
                title: "Interface"
                subtitle: "Bar and launcher"
                family: FontService.resolvedInterfaceFont
                preview: "The quick brown fox · 0123456789"
                onChoose: root.openPicker("interface")
            }

            // ── Terminal font ────────────────────────────────────────────
            FontCard {
                Layout.fillWidth: true
                icon: Icons.code
                title: "Terminal"
                subtitle: "New Foot windows"
                family: FontService.resolvedTerminalFont
                preview: "kolir ~ $ 0123456789 · {}[]()"
                onChoose: root.openPicker("terminal")
            }

            // ── Obsidian ─────────────────────────────────────────────────
            Rectangle {
                id: obsidianCard

                Layout.fillWidth: true
                implicitHeight: obsidianColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: FontService.obsidianFollows
                    ? Colors.withAlpha(Colors.primary, 0.35)
                    : Colors.withAlpha(Colors.outlineVariant, 0.22)

                Behavior on border.color {
                    ColorAnimation {
                        duration: Motion.color
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Motion.standardDecelerateCurve
                    }
                }

                ColumnLayout {
                    id: obsidianColumn

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            Layout.alignment: Qt.AlignVCenter
                            radius: Dimensions.radius.small + 2
                            color: FontService.obsidianFollows
                                ? Colors.primaryContainer
                                : Colors.surfaceContainerHighest

                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.color
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Motion.standardDecelerateCurve
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: Icons.code
                                color: FontService.obsidianFollows
                                    ? Colors.onPrimaryContainer
                                    : Colors.onSurfaceVariant
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
                                text: "Obsidian"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.obsidianStatus
                                color: root.obsidianFailed
                                    ? Colors.error
                                    : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: FontService.obsidianFollows
                            onToggled: value => FontService.setObsidianFollows(value)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Interface text and code blocks follow the two fonts "
                            + "above through the enabled kolir-font snippet."
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: FontService.applyError !== ""
                text: FontService.applyError
                color: Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                wrapMode: Text.Wrap
            }
        }
    }

    // ── Local components ───────────────────────────────────────────────────
    component ActionChip: Rectangle {
        id: chip

        property string label: ""

        signal clicked()

        readonly property bool hovered: chipMouse.containsMouse

        implicitWidth: chipText.implicitWidth + 20
        implicitHeight: 26
        radius: Dimensions.radius.full
        color: chip.hovered
            ? Colors.withAlpha(Colors.primary, 0.14)
            : Colors.surfaceContainerHighest
        border.width: 1
        border.color: chip.hovered
            ? Colors.withAlpha(Colors.primary, 0.5)
            : Colors.withAlpha(Colors.outlineVariant, 0.3)

        Behavior on color {
            ColorAnimation {
                duration: Motion.fade
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.fade
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }

        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.label
            color: chip.hovered ? Colors.primary : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component FontCard: Rectangle {
        id: card

        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property string family: ""
        property string preview: ""

        signal choose()

        implicitHeight: cardColumn.implicitHeight + 24
        radius: Dimensions.radius.medium
        color: Colors.surfaceContainerHigh
        border.width: 1
        border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

        ColumnLayout {
            id: cardColumn

            anchors {
                fill: parent
                margins: 12
            }
            spacing: 8

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
                        text: card.icon
                        color: Colors.primary
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
                        text: card.title
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                    }

                    Text {
                        Layout.fillWidth: true
                        text: card.subtitle
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: card.family
                        color: Colors.primary
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.medium
                        elide: Text.ElideRight
                    }
                }

                ActionChip {
                    label: "Change"
                    onClicked: card.choose()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Dimensions.radius.small
                color: Colors.surfaceContainerLowest
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                Text {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }
                    verticalAlignment: Text.AlignVCenter
                    text: card.preview
                    color: Colors.onSurface
                    font.family: card.family
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }
            }
        }
    }
}
