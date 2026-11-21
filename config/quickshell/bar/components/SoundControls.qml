import QtQuick
import QtQuick.Layouts
import "../../theme"
import "sound"

// Output/input volume, mute and device selection for PipeWire via
// AudioService (pactl under the hood), hosted by the bar volume popup.
Item {
    id: root

    readonly property var out: AudioService.activeSink
    readonly property var inp: AudioService.activeSource

    readonly property int outVolume: root.out ? AudioService.volumePercent(root.out) : AudioService.volume
    readonly property int inVolume: root.inp ? AudioService.volumePercent(root.inp) : 0

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
            AudioDeviceCard {
                id: outputCard

                title: "Output"
                device: root.out
                deviceLabel: root.deviceLabel(root.out, "No output device")
                fallbackMuted: AudioService.muted
                volume: root.outVolume
                icon: root.iconFor("out", root.out)
                mutedIcon: Icons.volumeOff
                normalIcon: Icons.volumeMute

                onMuteClicked: AudioService.toggleOutputMute()
                onVolumeMoved: value => AudioService.setOutputVolume(value)
                onVolumeDragStarted: value => AudioService.setOutputVolume(value)
                onVolumeDragUpdated: value => AudioService.setOutputVolume(value)
                onVolumeWheelMoved: value => AudioService.setOutputVolume(value)

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

            // ── Input card ────────────────────────────────────────────────────
            AudioDeviceCard {
                id: inputCard

                title: "Input"
                device: root.inp
                deviceLabel: root.deviceLabel(root.inp, "No input device")
                volume: root.inVolume
                icon: root.iconFor("in", root.inp)
                mutedIcon: Icons.micOff
                normalIcon: Icons.mic

                onMuteClicked: AudioService.toggleInputMute()
                onVolumeMoved: value => AudioService.setInputVolume(value)
                onVolumeDragStarted: value => AudioService.setInputVolume(value)
                onVolumeDragUpdated: value => AudioService.setInputVolume(value)
                onVolumeWheelMoved: value => AudioService.setInputVolume(value)
            }

            // ── Device lists ──────────────────────────────────────────────────
            AudioDeviceList {
                title: "Output devices"
                model: AudioService.sinks
                emptyIcon: Icons.volumeOff
                emptyLabel: "No output devices"
                onDeviceActivated: name => AudioService.setDefaultSink(name)
            }

            AudioDeviceList {
                title: "Input devices"
                model: AudioService.sources
                emptyIcon: Icons.mic
                emptyLabel: "No input devices"
                onDeviceActivated: name => AudioService.setDefaultSource(name)
            }
        }
    }
}
