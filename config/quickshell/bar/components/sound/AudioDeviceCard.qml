import QtQuick
import QtQuick.Layouts
import "../../../theme"
import ".."

// One device card in the sound popup: icon, title, device name, live volume,
// mute button and the volume slider. Output and input cards share it; the
// caller supplies the resolved icon set and applies the volume changes.
Rectangle {
    id: root

    property string title: ""
    property string deviceLabel: ""
    property var device: null
    property bool fallbackMuted: false
    property int volume: 0

    property string icon: ""
    property string mutedIcon: ""
    property string normalIcon: ""

    signal muteClicked()
    signal volumeMoved(real value)
    signal volumeDragStarted(real value)
    signal volumeDragUpdated(real value)
    signal volumeWheelMoved(real value)

    default property alias extraContent: cardCol.data

    // Local slider position while dragging, so the track doesn't fight the
    // service state mid-drag. After release we keep the local value briefly
    // until pactl reports the new volume back.
    property bool dragging: false
    property real dragValue: 0

    readonly property bool deviceMuted: device ? device.muted : false
    readonly property bool muted: device ? device.muted : fallbackMuted
    readonly property int displayVolume: dragging ? Math.round(dragValue) : volume

    Timer {
        id: settleTimer

        interval: 350
        repeat: false
        onTriggered: root.dragging = false
    }

    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

    ColumnLayout {
        id: cardCol

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
                color: root.device && !root.device.muted
                    ? Colors.primaryContainer
                    : Colors.surfaceContainerHighest

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: root.device && !root.device.muted
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
                    text: root.title
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.bodyMedium
                    font.weight: Typography.weight.medium
                }

                Text {
                    Layout.fillWidth: true
                    text: root.deviceLabel
                    color: root.device && !root.device.muted ? Colors.primary : Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                width: 38
                horizontalAlignment: Text.AlignRight
                text: root.deviceMuted ? "Mute" : (root.displayVolume + "%")
                color: root.deviceMuted ? Colors.error : Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelLarge
                font.weight: Typography.weight.bold
                elide: Text.ElideRight
            }

            Rectangle {
                id: muteButton

                property bool hovered: false

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: Dimensions.radius.full
                color: Colors.surfaceContainerLowest
                border.width: 1
                border.color: root.deviceMuted
                    ? Colors.withAlpha(Colors.error, 0.7)
                    : muteButton.hovered
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.35)
                opacity: root.device ? 1.0 : 0.45

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                StateLayer {
                    shown: muteButton.hovered
                    strength: 0.16
                }

                Text {
                    anchors.centerIn: parent
                    text: root.deviceMuted ? root.mutedIcon : root.normalIcon
                    color: root.deviceMuted ? Colors.error : Colors.onSurface
                    font.family: Typography.iconFont
                    font.pixelSize: Dimensions.icon.small + 2
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !!root.device
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: muteButton.hovered = containsMouse
                    onClicked: root.muteClicked()
                }
            }
        }

        VolumeSlider {
            Layout.fillWidth: true
            value: root.dragging ? root.dragValue : root.volume
            muted: root.muted
            interactive: !!root.device
            onMoved: value => {
                root.dragValue = value;
                root.volumeMoved(value);
                settleTimer.restart();
            }
            onDragStarted: value => {
                settleTimer.stop();
                root.dragging = true;
                root.dragValue = value;
                root.volumeDragStarted(value);
            }
            onDragUpdated: value => {
                root.dragValue = value;
                root.volumeDragUpdated(value);
            }
            onWheelMoved: value => {
                root.dragging = true;
                root.dragValue = value;
                root.volumeWheelMoved(value);
                settleTimer.restart();
            }
        }
    }
}
