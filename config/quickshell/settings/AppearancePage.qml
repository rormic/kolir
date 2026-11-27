pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import "../theme"
import "../services"
import "../bar/components"

// Matugen appearance page: scheme type, contrast and light/dark/auto mode.
// Choices are persisted and applied by AppearanceService, which reruns
// generate-colors.sh; Colors.qml then reloads the palette in place, so the
// shell never restarts for a theme change.
Item {
    id: root

    signal back()

    property int topInset: 0
    // True while the settings sheet itself is open; combined with `visible`
    // it decides whether the palette preview worker should run.
    property bool active: true

    implicitWidth: 380
    // Mirrors `appearanceHeight` in SettingsMenu.qml. Tall enough for the
    // resting cards so the page does not open with a sliver of scroll.
    implicitHeight: 1002

    // Local slider position while dragging or after a wheel change, so the
    // handle follows the pointer without waiting for a regeneration.
    property bool dragging: false
    property real dragPercent: 0

    // Name shown next to "Scheme type": the hovered tile while the pointer is
    // over the palette grid, otherwise the selected scheme.
    property string hoveredScheme: ""
    readonly property string schemeHint: root.hoveredScheme !== ""
        ? AppearanceService.labelFor(root.hoveredScheme)
        : AppearanceService.labelFor(AppearanceService.schemeType)
    readonly property bool paletteReady: Object.keys(AppearanceService.palettePreviews).length > 0
    readonly property bool previewFailed: !AppearanceService.previewsLoading
        && !root.paletteReady && AppearanceService.previewsError !== ""

    readonly property real contrastValue: root.dragging
        ? root.percentToContrast(root.dragPercent)
        : AppearanceService.contrast
    readonly property string contrastLabel: (root.contrastValue > 0 ? "+" : "")
        + root.contrastValue.toFixed(2)

    readonly property var modeOptions: [
        { value: "auto", label: "Auto", icon: Icons.brightnessAuto },
        { value: "light", label: "Light", icon: Icons.lightMode },
        { value: "dark", label: "Dark", icon: Icons.darkMode },
    ]

    function percentToContrast(percent) {
        return Math.round(((percent / 50) - 1) * 100) / 100;
    }

    function contrastToPercent(contrast) {
        return (contrast + 1) * 50;
    }

    function applyContrastPreset(value) {
        contrastSettleTimer.stop();
        root.dragging = false;
        AppearanceService.setContrast(value);
    }

    // VolumeSlider assigns `value` itself while dragging, so a plain binding
    // would be destroyed after the first drag. Keep the handle in sync
    // explicitly whenever the service value changes outside a drag.
    function syncContrastSlider() {
        contrastSlider.value = root.contrastToPercent(AppearanceService.contrast);
    }

    function updatePreviewsVisibility() {
        AppearanceService.setPreviewsVisible(root.visible && root.active);
    }

    onVisibleChanged: {
        if (!root.visible)
            root.hoveredScheme = "";
        root.updatePreviewsVisibility();
        if (root.visible && root.active)
            cursorPreviewTimer.restart();
    }

    onActiveChanged: {
        if (!root.active)
            root.hoveredScheme = "";
        root.updatePreviewsVisibility();
        if (root.visible && root.active)
            cursorPreviewTimer.restart();
    }

    onDraggingChanged: {
        if (!root.dragging)
            root.syncContrastSlider();
    }

    Component.onCompleted: root.syncContrastSlider()

    // ── Cursor preview ─────────────────────────────────────────────────────
    // The cursor row shows the pointer the machine actually has installed, so
    // the switch is not an anonymous glyph. The helper renders the theme's
    // default arrow, and the row re-reads it after every apply.
    property string cursorPreviewLight: ""
    property string cursorPreviewDark: ""
    property bool cursorPreviewPaired: false

    function updateCursorPreview() {
        if (!root.visible || !root.active)
            return;
        if (cursorPreview.running)
            cursorPreview.running = false;
        cursorPreview.running = true;
    }

    function applyCursorPreview(text) {
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            parsed = null;
        }

        if (!parsed || !parsed.ok || !parsed.light || !parsed.dark) {
            root.cursorPreviewLight = "";
            root.cursorPreviewDark = "";
            root.cursorPreviewPaired = false;
            return;
        }

        root.cursorPreviewPaired = parsed.paired === true;
        root.cursorPreviewLight = "file://" + parsed.light.path;
        root.cursorPreviewDark = "file://" + parsed.dark.path;
    }

    Timer {
        id: cursorPreviewTimer

        interval: 350
        repeat: false
        onTriggered: root.updateCursorPreview()
    }

    Process {
        id: cursorPreview

        running: false
        command: ["python3", ShellPaths.cursorPreviewScript, "--pair",
            "--pair-script", ShellPaths.hyprScripts + "/apply-cursor.sh",
            "--dir", ShellPaths.cursorPreviewDir, "--size", "64"]

        stdout: StdioCollector {
            onStreamFinished: root.applyCursorPreview(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    console.warn("AppearancePage: cursor preview: " + output);
            }
        }
    }

    Connections {
        target: AppearanceService

        function onCursorApplied() {
            cursorPreviewTimer.restart();
        }

        function onRegeneratingChanged() {
            if (!AppearanceService.regenerating)
                cursorPreviewTimer.restart();
        }
    }

    Timer {
        id: contrastSettleTimer

        interval: 400
        repeat: false
        onTriggered: root.dragging = false
    }

    // ── Header ─────────────────────────────────────────────────────────────
    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Appearance"
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

        ColumnLayout {
            id: body

            width: flick.width
            spacing: 10

            // ── Palette preview ───────────────────────────────────────────
            Rectangle {
                id: previewCard

                Layout.fillWidth: true
                implicitHeight: previewColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: previewColumn

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Current palette"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            text: AppearanceService.regenerating
                                ? "Updating…"
                                : AppearanceService.schemeLabel
                            color: AppearanceService.regenerating
                                ? Colors.onSurfaceVariant
                                : Colors.primary
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.medium
                        }
                    }

                    Row {
                        id: swatches

                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Primary", color: Colors.primary },
                                { label: "Secondary", color: Colors.secondary },
                                { label: "Tertiary", color: Colors.tertiary },
                                { label: "Error", color: Colors.error },
                                { label: "Surface", color: Colors.surfaceContainerHighest },
                            ]

                            delegate: Rectangle {
                                required property var modelData

                                width: Math.max(8,
                                    (swatches.width - swatches.spacing * 4) / 5)
                                height: 40
                                radius: Dimensions.radius.small
                                color: modelData.color
                                border.width: 1
                                border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Motion.color
                                        easing.type: Easing.Bezier
                                        easing.bezierCurve: Motion.standardDecelerateCurve
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Scheme type ───────────────────────────────────────────────
            Rectangle {
                id: schemeCard

                Layout.fillWidth: true
                implicitHeight: schemeColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: schemeColumn

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
                            text: "Scheme type"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            text: AppearanceService.previewsLoading
                                ? "Preparing…"
                                : root.previewFailed
                                    ? "Preview unavailable"
                                    : root.schemeHint
                            color: root.previewFailed ? Colors.error : Colors.primary
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.medium
                        }
                    }

                    // Each option is a segmented circle built from its own
                    // palette. The name appears in the header on hover, so the
                    // picker itself stays colour-first.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        columnSpacing: 6
                        rowSpacing: 8

                        Repeater {
                            model: AppearanceService.schemeTypes

                            delegate: Item {
                                id: paletteTile

                                required property var modelData

                                readonly property var paletteData: AppearanceService.palettePreviews[paletteTile.modelData.value]
                                readonly property bool active: AppearanceService.schemeType
                                    === paletteTile.modelData.value
                                readonly property bool hovered: paletteMouse.containsMouse

                                Layout.fillWidth: true
                                Layout.preferredHeight: 60

                                PaletteSwatch {
                                    anchors.centerIn: parent
                                    primaryColor: paletteTile.paletteData
                                        && paletteTile.paletteData.primary
                                        ? paletteTile.paletteData.primary
                                        : paletteTile.active
                                            ? Colors.primary
                                            : Colors.surfaceContainerHighest
                                    secondaryColor: paletteTile.paletteData
                                        && paletteTile.paletteData.secondary
                                        ? paletteTile.paletteData.secondary
                                        : paletteTile.active
                                            ? Colors.secondary
                                            : Colors.surfaceContainerHighest
                                    tertiaryColor: paletteTile.paletteData
                                        && paletteTile.paletteData.tertiary
                                        ? paletteTile.paletteData.tertiary
                                        : paletteTile.active
                                            ? Colors.tertiary
                                            : Colors.surfaceContainerHighest
                                    selected: paletteTile.active
                                    hovered: paletteTile.hovered
                                }

                                MouseArea {
                                    id: paletteMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.hoveredScheme = paletteTile.modelData.value
                                    onExited: {
                                        if (root.hoveredScheme === paletteTile.modelData.value)
                                            root.hoveredScheme = "";
                                    }
                                    onClicked: AppearanceService.setSchemeType(
                                        paletteTile.modelData.value)
                                }
                            }
                        }
                    }
                }
            }

            // ── Contrast ──────────────────────────────────────────────────
            Rectangle {
                id: contrastCard

                Layout.fillWidth: true
                implicitHeight: contrastColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: contrastColumn

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
                            text: "Contrast"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            text: root.contrastLabel
                            color: Colors.primary
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }
                    }

                    VolumeSlider {
                        id: contrastSlider

                        Layout.fillWidth: true
                        onDragStarted: value => {
                            contrastSettleTimer.stop();
                            root.dragging = true;
                            root.dragPercent = value;
                            AppearanceService.setContrast(root.percentToContrast(value));
                        }
                        onDragUpdated: value => {
                            root.dragPercent = value;
                            AppearanceService.setContrast(root.percentToContrast(value));
                        }
                        onMoved: value => {
                            root.dragPercent = value;
                            root.dragging = false;
                            AppearanceService.setContrast(root.percentToContrast(value));
                        }
                        onWheelMoved: value => {
                            root.dragging = true;
                            root.dragPercent = value;
                            AppearanceService.setContrast(root.percentToContrast(value));
                            contrastSettleTimer.restart();
                        }
                    }

                    Connections {
                        target: AppearanceService

                        function onContrastChanged() {
                            if (!root.dragging)
                                root.syncContrastSlider();
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24

                        ContrastPreset {
                            anchors.left: parent.left
                            value: -1
                            onChosen: root.applyContrastPreset(-1)
                        }

                        ContrastPreset {
                            anchors.horizontalCenter: parent.horizontalCenter
                            value: 0
                            onChosen: root.applyContrastPreset(0)
                        }

                        ContrastPreset {
                            anchors.right: parent.right
                            value: 1
                            onChosen: root.applyContrastPreset(1)
                        }
                    }
                }
            }

            // ── Theme mode ────────────────────────────────────────────────
            Rectangle {
                id: modeCard

                Layout.fillWidth: true
                implicitHeight: modeColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: modeColumn

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
                            text: "Theme mode"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.bold
                        }

                        Text {
                            text: AppearanceService.mode === "auto"
                                ? "Sunrise / sunset"
                                : "Fixed"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.modeOptions

                            delegate: Rectangle {
                                id: modeChip

                                required property var modelData

                                readonly property bool active: AppearanceService.mode
                                    === modeChip.modelData.value
                                readonly property bool hovered: modeMouse.containsMouse

                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: Dimensions.radius.full
                                color: modeChip.active
                                    ? Colors.primaryContainer
                                    : Colors.surfaceContainerLowest
                                border.width: 1
                                border.color: modeChip.active
                                    ? Colors.withAlpha(Colors.primary, 0.7)
                                    : modeChip.hovered
                                        ? Colors.withAlpha(Colors.primary, 0.45)
                                        : Colors.withAlpha(Colors.outlineVariant, 0.35)

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

                                StateLayer {
                                    shown: modeChip.hovered && !modeChip.active
                                    strength: 0.12
                                    duration: Motion.fade
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modeChip.modelData.icon
                                        color: modeChip.active
                                            ? Colors.onPrimaryContainer
                                            : Colors.onSurfaceVariant
                                        font.family: Typography.iconFont
                                        font.pixelSize: Dimensions.icon.small
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modeChip.modelData.label
                                        color: modeChip.active
                                            ? Colors.onPrimaryContainer
                                            : modeChip.hovered
                                                ? Colors.primary
                                                : Colors.onSurfaceVariant
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelSmall
                                        font.weight: modeChip.active
                                            ? Typography.weight.bold
                                            : Typography.weight.medium
                                    }
                                }

                                MouseArea {
                                    id: modeMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: AppearanceService.setMode(
                                        modeChip.modelData.value)
                                }
                            }
                        }
                    }

                    // Auto follows the same location and solar times as the
                    // night-light schedule, so the switch is visible before it
                    // happens instead of being an unexplained toggle.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: Icons.place
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: HyprsunsetService.locationLabel
                            color: HyprsunsetService.locationAvailable
                                ? Colors.onSurface
                                : Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.medium
                            elide: Text.ElideRight
                        }

                        IconButton {
                            Layout.alignment: Qt.AlignVCenter
                            icon: Icons.refresh
                            iconSize: Dimensions.icon.small + 2
                            enabled: !HyprsunsetService.locationRefreshing
                            opacity: HyprsunsetService.locationRefreshing ? 0.5 : 1.0
                            onClicked: HyprsunsetService.refreshLocation(true)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        SunTimeCard {
                            Layout.fillWidth: true
                            icon: Icons.lightMode
                            value: HyprsunsetService.sunriseLabel
                        }

                        SunTimeCard {
                            Layout.fillWidth: true
                            icon: Icons.darkMode
                            value: HyprsunsetService.sunsetLabel
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: AppearanceService.autoStatusText
                        color: AppearanceService.autoPaused
                            ? Colors.error
                            : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.Wrap
                    }

                    // Palette crossfade. Colors.qml animates every generated
                    // color; switching this off applies them instantly, which
                    // is the escape hatch for slow machines.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: "Crossfade palette"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Animate color changes between themes"
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: AppearanceService.crossfade
                            onToggled: value => AppearanceService.setCrossfade(value)
                        }
                    }

                    // Cursor variant. The machine's cursor theme comes from
                    // user.lua (XCURSOR_THEME); apply-cursor.sh swaps its
                    // light/dark token so the pointer matches the palette. The
                    // row paints both real pointers of that pair with an arrow
                    // between them, so the switch shows exactly what changes.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: "Cursor theme"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.bodyMedium
                            font.weight: Typography.weight.medium
                        }

                        // Light pointer, then the dark one: both read from the
                        // installed theme by cursor-preview.py.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredHeight: 34
                            Layout.preferredWidth: cursorPair.implicitWidth + 16
                            radius: Dimensions.radius.small + 2
                            color: Colors.surfaceContainerHighest
                            border.width: 1
                            border.color: Colors.withAlpha(Colors.outlineVariant, 0.35)

                            Row {
                                id: cursorPair

                                anchors.centerIn: parent
                                spacing: 6

                                Image {
                                    id: lightCursorImage

                                    width: 24
                                    height: 24
                                    source: root.cursorPreviewLight
                                    sourceSize.width: 60
                                    sourceSize.height: 60
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    visible: status === Image.Ready
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.cursorPreviewPaired
                                    text: Icons.arrowForward
                                    color: Colors.onSurfaceVariant
                                    font.family: Typography.iconFont
                                    font.pixelSize: Dimensions.icon.small + 2
                                }

                                Image {
                                    id: darkCursorImage

                                    width: 24
                                    height: 24
                                    source: root.cursorPreviewDark
                                    sourceSize.width: 60
                                    sourceSize.height: 60
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    visible: root.cursorPreviewPaired
                                        && status === Image.Ready
                                }
                            }

                            // Shown until the helper answers, or when the theme
                            // ships a pointer this build cannot read.
                            Text {
                                anchors.centerIn: parent
                                visible: lightCursorImage.status !== Image.Ready
                                text: Icons.pointer
                                color: Colors.onSurfaceVariant
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.extraLarge
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: AppearanceService.cursorFollowsTheme
                            onToggled: value => AppearanceService.setCursorFollowsTheme(value)
                        }
                    }
                }
            }

            FrameCard {
                Layout.fillWidth: true
            }
        }
    }

    // Small contrast preset pill. The caller anchors it to the left, centre
    // or right edge so the three values line up with the slider scale.
    component ContrastPreset: Rectangle {
        id: preset

        property real value: 0

        signal chosen()

        readonly property bool active: Math.abs(
            AppearanceService.contrast - preset.value) < 0.005
        readonly property bool hovered: presetMouse.containsMouse

        implicitWidth: presetLabel.implicitWidth + 20
        implicitHeight: 24
        radius: Dimensions.radius.full
        color: preset.active
            ? Colors.primaryContainer
            : Colors.surfaceContainerLowest
        border.width: 1
        border.color: preset.active
            ? Colors.withAlpha(Colors.primary, 0.7)
            : preset.hovered
                ? Colors.withAlpha(Colors.primary, 0.45)
                : Colors.withAlpha(Colors.outlineVariant, 0.35)

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

        StateLayer {
            shown: preset.hovered && !preset.active
            strength: 0.12
            duration: Motion.fade
        }

        Text {
            id: presetLabel

            anchors.centerIn: parent
            text: preset.value > 0 ? "+" + preset.value : String(preset.value)
            color: preset.active
                ? Colors.onPrimaryContainer
                : preset.hovered
                    ? Colors.primary
                    : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: preset.active
                ? Typography.weight.bold
                : Typography.weight.medium
        }

        MouseArea {
            id: presetMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: preset.chosen()
        }
    }

    // Colour-first scheme swatch: a segmented circle in the style of the
    // Android wallpaper picker. The name is shown in the card header, so the
    // control itself stays purely visual.
    component PaletteSwatch: Item {
        id: swatch

        property color primaryColor: Colors.primary
        property color secondaryColor: Colors.secondary
        property color tertiaryColor: Colors.tertiary
        property bool selected: false
        property bool hovered: false

        implicitWidth: 60
        implicitHeight: 60

        scale: swatch.hovered ? 1.04 : 1.0
        Behavior on scale {
            SpringAnimation {
                spring: Motion.spatialSpringFast
                damping: Motion.spatialSpringFastDamping
                epsilon: Motion.springScaleEpsilon
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: swatch.selected ? 2 : 1
            border.color: swatch.selected
                ? Colors.primary
                : swatch.hovered
                    ? Colors.withAlpha(Colors.primary, 0.6)
                    : Colors.withAlpha(Colors.outlineVariant, 0.45)

            Behavior on border.color {
                ColorAnimation {
                    duration: Motion.fade
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }
        }

        Shape {
            width: 46
            height: 46
            anchors.centerIn: parent
            preferredRendererType: Shape.CurveRenderer

            // Top half primary, bottom-left secondary, bottom-right tertiary.
            ShapePath {
                fillColor: swatch.primaryColor
                strokeWidth: 0
                PathSvg { path: "M 23 23 L 0 23 A 23 23 0 0 1 46 23 Z" }
            }

            ShapePath {
                fillColor: swatch.secondaryColor
                strokeWidth: 0
                PathSvg { path: "M 23 23 L 23 46 A 23 23 0 0 1 0 23 Z" }
            }

            ShapePath {
                fillColor: swatch.tertiaryColor
                strokeWidth: 0
                PathSvg { path: "M 23 23 L 46 23 A 23 23 0 0 1 23 46 Z" }
            }
        }
    }

}
