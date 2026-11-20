import QtQuick
import QtQuick.Layouts
import "../../theme"

// Output/input volume, mute and device selection for PipeWire via
// AudioService (pactl under the hood), hosted by the bar volume popup.
Item {
    id: root

    // Local slider position while dragging, so the track doesn't fight the
    // service state mid-drag. After release we keep the local value briefly
    // until pactl reports the new volume back.
    property bool draggingOutput: false
    property real dragOutputValue: 0
    property bool draggingInput: false
    property real dragInputValue: 0

    Timer {
        id: outputSettleTimer
        interval: 350
        repeat: false
        onTriggered: root.draggingOutput = false
    }

    Timer {
        id: inputSettleTimer
        interval: 350
        repeat: false
        onTriggered: root.draggingInput = false
    }

    readonly property var out: AudioService.activeSink
    readonly property var inp: AudioService.activeSource

    readonly property int outVolume: root.out ? AudioService.volumePercent(root.out) : AudioService.volume
    readonly property int inVolume: root.inp ? AudioService.volumePercent(root.inp) : 0
    // While dragging, show the live local value so the number tracks the
    // handle instead of waiting for pactl to confirm the change.
    readonly property int displayOutputVolume: root.draggingOutput ? Math.round(root.dragOutputValue) : root.outVolume
    readonly property int displayInputVolume: root.draggingInput ? Math.round(root.dragInputValue) : root.inVolume

    // Codec switching only applies to the A2DP profiles of a Bluetooth sink.
    readonly property var btCard: root.out ? AudioService.cardForSink(root.out.name) : null
    readonly property var codecProfiles: {
        if (!root.btCard || !Array.isArray(root.btCard.profiles))
            return [];
        return root.btCard.profiles.filter(p => (p.name || "").startsWith("a2dp-sink"));
    }
    readonly property bool showCodec: root.codecProfiles.length > 0

    function iconFor(kind, device) {
        const muted = kind === "out" ? (root.out ? root.out.muted : AudioService.muted)
                                    : (root.inp ? root.inp.muted : false);
        const cls = device && device.icon ? device.icon : "";

        if (muted)
            return kind === "out" ? Icons.volumeOff : Icons.micOff;

        if (kind === "out") {
            if (cls.includes("headset"))
                return Icons.headphones;
            return Icons.volumeUp;
        }

        if (cls.includes("headset"))
            return Icons.headphones;
        return Icons.mic;
    }

    function deviceLabel(device, fallback) {
        if (!device || !device.description)
            return fallback;
        return device.description;
    }

    // PipeWire puts the actual codec in the profile description
    // ("... (A2DP Sink, codec AAC)"); the bare "a2dp-sink" profile is AAC,
    // not a generic auto mode. Fall back to the profile-name suffix.
    function codecLabel(profile) {
        const labels = {
            "": "Auto",
            "sbc": "SBC",
            "sbc_xq": "SBC-XQ",
            "sbc-xq": "SBC-XQ",
            "aac": "AAC",
            "ldac": "LDAC",
            "aptx": "aptX",
            "aptx_hd": "aptX HD",
            "aptx-hd": "aptX HD",
            "aptx_ll": "aptX LL",
            "aptx_ll_duplex": "aptX LL",
            "aptx_adaptive": "aptX Adaptive",
            "faststream": "FastStream",
            "faststream_duplex": "FastStream",
            "opus_05": "Opus",
            "opus_05_pro": "Opus Pro",
            "lc3plus_h3": "LC3plus",
            "lc3": "LC3",
            "cvsd": "CVSD",
            "msbc": "mSBC"
        };
        const desc = String(profile && profile.description || "");
        const match = desc.match(/codec\s+([\w.+-]+)/i);
        const raw = match ? match[1]
                          : String(profile && profile.name || "").replace(/^a2dp-sink-?/, "");
        return labels[raw.toLowerCase()] || raw.toUpperCase();
    }

    // Called when the popup opens: the controls stay alive while the popup
    // window is hidden, so visibility changes are not enough to detect this.
    function refresh() {
        flick.contentY = 0;
        refreshDelay.restart();
    }

    Timer {
        id: refreshDelay
        interval: 120
        repeat: false
        onTriggered: AudioService.refresh()
    }

    Flickable {
        id: flick

        anchors {
            fill: parent
            margins: 14
        }
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body

            width: flick.width
            spacing: 12

            // ── Output card ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: outCol.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: outCol

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
                            color: root.out && !root.out.muted
                                ? Colors.primaryContainer
                                : Colors.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: root.iconFor("out", root.out)
                                color: root.out && !root.out.muted
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
                                text: "Output"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.deviceLabel(root.out, "No output device")
                                color: root.out && !root.out.muted ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            width: 38
                            horizontalAlignment: Text.AlignRight
                            text: root.out && root.out.muted ? "Mute" : (root.displayOutputVolume + "%")
                            color: root.out && root.out.muted ? Colors.error : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelLarge
                            font.weight: Typography.weight.bold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: outMuteBtn
                            property bool hovered: false
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            Layout.alignment: Qt.AlignVCenter
                            radius: Dimensions.radius.full
                            color: outMuteBtn.hovered
                                ? Colors.stateLayer(Colors.primary, 0.16)
                                : Colors.surfaceContainerLowest
                            border.width: 1
                            border.color: root.out && root.out.muted
                                ? Colors.withAlpha(Colors.error, 0.7)
                                : outMuteBtn.hovered
                                    ? Colors.withAlpha(Colors.primary, 0.6)
                                    : Colors.withAlpha(Colors.outlineVariant, 0.35)
                            opacity: root.out ? 1.0 : 0.45

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: root.out && root.out.muted ? Icons.volumeOff : Icons.volumeMute
                                color: root.out && root.out.muted ? Colors.error : Colors.onSurface
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.small + 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !!root.out
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: outMuteBtn.hovered = containsMouse
                                onClicked: AudioService.toggleOutputMute()
                            }
                        }
                    }

                    VolumeSlider {
                        Layout.fillWidth: true
                        value: root.draggingOutput ? root.dragOutputValue : root.outVolume
                        muted: root.out ? root.out.muted : AudioService.muted
                        interactive: !!root.out
                        onMoved: value => {
                            root.dragOutputValue = value;
                            AudioService.setOutputVolume(value);
                            outputSettleTimer.restart();
                        }
                        onDragStarted: value => {
                            outputSettleTimer.stop();
                            root.draggingOutput = true;
                            root.dragOutputValue = value;
                            AudioService.setOutputVolume(value);
                        }
                        onDragUpdated: value => {
                            root.dragOutputValue = value;
                            AudioService.setOutputVolume(value);
                        }
                        onWheelMoved: value => {
                            root.draggingOutput = true;
                            root.dragOutputValue = value;
                            AudioService.setOutputVolume(value);
                            outputSettleTimer.restart();
                        }
                    }

                    // ── Bluetooth codec chips ─────────────────────────────
                    // Only the A2DP profiles the headset advertises are listed.
                    // PipeWire exposes one profile per codec; the bare
                    // "a2dp-sink" profile carries AAC.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.showCodec

                        Text {
                            Layout.fillWidth: true
                            text: "Bluetooth codec"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.medium
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.codecProfiles

                                delegate: Rectangle {
                                    id: codecChip

                                    required property var modelData

                                    readonly property bool active: root.btCard
                                        && root.btCard.activeProfile === modelData.name
                                    readonly property bool hovered: codecHover.hovered

                                    width: codecText.implicitWidth + 20
                                    height: 26
                                    radius: Dimensions.radius.full
                                    color: codecChip.active
                                        ? Colors.primaryContainer
                                        : codecChip.hovered
                                            ? Colors.stateLayer(Colors.primary, 0.12)
                                            : Colors.surfaceContainerLowest
                                    border.width: 1
                                    border.color: codecChip.active
                                        ? Colors.withAlpha(Colors.primary, 0.7)
                                        : Colors.withAlpha(Colors.outlineVariant, 0.35)

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    HoverHandler { id: codecHover }

                                    Text {
                                        id: codecText
                                        anchors.centerIn: parent
                                        text: root.codecLabel(codecChip.modelData)
                                        color: codecChip.active
                                            ? Colors.onPrimaryContainer
                                            : Colors.onSurfaceVariant
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelSmall
                                        font.weight: codecChip.active
                                            ? Typography.weight.bold
                                            : Typography.weight.medium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !codecChip.active
                                        onClicked: AudioService.setCardProfile(root.btCard.name,
                                                                               codecChip.modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Input card ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: inCol.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: inCol

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
                            color: root.inp && !root.inp.muted
                                ? Colors.primaryContainer
                                : Colors.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: root.iconFor("in", root.inp)
                                color: root.inp && !root.inp.muted
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
                                text: "Input"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.deviceLabel(root.inp, "No input device")
                                color: root.inp && !root.inp.muted ? Colors.primary : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            width: 38
                            horizontalAlignment: Text.AlignRight
                            text: root.inp && root.inp.muted ? "Mute" : (root.displayInputVolume + "%")
                            color: root.inp && root.inp.muted ? Colors.error : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelLarge
                            font.weight: Typography.weight.bold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: inMuteBtn
                            property bool hovered: false
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            Layout.alignment: Qt.AlignVCenter
                            radius: Dimensions.radius.full
                            color: inMuteBtn.hovered
                                ? Colors.stateLayer(Colors.primary, 0.16)
                                : Colors.surfaceContainerLowest
                            border.width: 1
                            border.color: root.inp && root.inp.muted
                                ? Colors.withAlpha(Colors.error, 0.7)
                                : inMuteBtn.hovered
                                    ? Colors.withAlpha(Colors.primary, 0.6)
                                    : Colors.withAlpha(Colors.outlineVariant, 0.35)
                            opacity: root.inp ? 1.0 : 0.45

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: root.inp && root.inp.muted ? Icons.micOff : Icons.mic
                                color: root.inp && root.inp.muted ? Colors.error : Colors.onSurface
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.small + 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !!root.inp
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: inMuteBtn.hovered = containsMouse
                                onClicked: AudioService.toggleInputMute()
                            }
                        }
                    }

                    VolumeSlider {
                        Layout.fillWidth: true
                        value: root.draggingInput ? root.dragInputValue : root.inVolume
                        muted: root.inp ? root.inp.muted : false
                        interactive: !!root.inp
                        onMoved: value => {
                            root.dragInputValue = value;
                            AudioService.setInputVolume(value);
                            inputSettleTimer.restart();
                        }
                        onDragStarted: value => {
                            inputSettleTimer.stop();
                            root.draggingInput = true;
                            root.dragInputValue = value;
                            AudioService.setInputVolume(value);
                        }
                        onDragUpdated: value => {
                            root.dragInputValue = value;
                            AudioService.setInputVolume(value);
                        }
                        onWheelMoved: value => {
                            root.draggingInput = true;
                            root.dragInputValue = value;
                            AudioService.setInputVolume(value);
                            inputSettleTimer.restart();
                        }
                    }
                }
            }

            // ── Device lists ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Output devices"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }

                Text {
                    text: AudioService.sinks.length + (AudioService.sinks.length === 1 ? " device" : " devices")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                radius: Dimensions.radius.medium
                color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
                clip: true

                ListView {
                    id: sinkList

                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: AudioService.sinks

                    delegate: Item {
                        id: sinkRow

                        required property var modelData

                        width: sinkList.width
                        height: 34

                        readonly property bool hovered: sinkHover.hovered
                        readonly property bool active: modelData.isDefault

                        HoverHandler { id: sinkHover }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Dimensions.radius.small
                            color: sinkRow.active
                                ? Colors.withAlpha(Colors.primary, 0.14)
                                : sinkRow.hovered
                                    ? Colors.stateLayer(Colors.onSurface, 0.06)
                                    : "transparent"
                            border.width: sinkRow.active ? 1 : 0
                            border.color: Colors.withAlpha(Colors.primary, 0.45)

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: sinkRow.active
                            text: Icons.check
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }

                        Column {
                            anchors {
                                left: parent.left
                                leftMargin: sinkRow.active ? 36 : 12
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 0

                            Text {
                                width: parent.width
                                text: modelData.description || modelData.name || "Unknown device"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: sinkRow.active ? Typography.weight.bold : Typography.weight.medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!sinkRow.active)
                                    AudioService.setDefaultSink(modelData.name);
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: sinkList.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Icons.volumeOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                        font.family: Typography.iconFont
                        font.pixelSize: 24
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No output devices"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Input devices"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.bold
                }

                Text {
                    text: AudioService.sources.length + (AudioService.sources.length === 1 ? " device" : " devices")
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                radius: Dimensions.radius.medium
                color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
                clip: true

                ListView {
                    id: sourceList

                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: AudioService.sources

                    delegate: Item {
                        id: sourceRow

                        required property var modelData

                        width: sourceList.width
                        height: 34

                        readonly property bool hovered: sourceHover.hovered
                        readonly property bool active: modelData.isDefault

                        HoverHandler { id: sourceHover }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Dimensions.radius.small
                            color: sourceRow.active
                                ? Colors.withAlpha(Colors.primary, 0.14)
                                : sourceRow.hovered
                                    ? Colors.stateLayer(Colors.onSurface, 0.06)
                                    : "transparent"
                            border.width: sourceRow.active ? 1 : 0
                            border.color: Colors.withAlpha(Colors.primary, 0.45)

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: sourceRow.active
                            text: Icons.check
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }

                        Column {
                            anchors {
                                left: parent.left
                                leftMargin: sourceRow.active ? 36 : 12
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 0

                            Text {
                                width: parent.width
                                text: modelData.description || modelData.name || "Unknown device"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: sourceRow.active ? Typography.weight.bold : Typography.weight.medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!sourceRow.active)
                                    AudioService.setDefaultSource(modelData.name);
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: sourceList.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Icons.mic
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.5)
                        font.family: Typography.iconFont
                        font.pixelSize: 24
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No input devices"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                    }
                }
            }
        }
    }
}
