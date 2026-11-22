import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../theme"
import "../../services"
import "nightLight"

// Night-light sheet for the brightness pill. The surface, scrim, reveal and
// dismissal come from EmbeddedSheet (mirrored: the body sits on the right
// frame edge and the shoulder on its left); this file owns the controls. Left
// click opens it, Escape or an outside click closes it. The hyprsunset IPC
// stays on HyprsunsetService.
EmbeddedSheet {
    id: root

    mirror: true
    panelHeight: 540

    readonly property string statusText: {
        if (!HyprsunsetService.available)
            return "hyprsunset is not running";

        const state = HyprsunsetService.enabled ? "On" : "Off";
        let text = state + " · " + HyprsunsetService.temperature + " K";

        if (HyprsunsetService.scheduleActive && HyprsunsetService.scheduleLabel !== "")
            text += " · " + HyprsunsetService.scheduleLabel;

        return text;
    }

    function open() {
        if (root.opened)
            return;

        HyprsunsetService.refresh();
        if (HyprsunsetService.sunMode)
            HyprsunsetService.refreshLocation(false);

        root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        temperatureCard.cancelDrag();
        root.revealClose();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    onDismissalRequested: root.close()

    Keys.onEscapePressed: function (event) {
        root.close();
        event.accepted = true;
    }

    IpcHandler {
        target: "nightLight"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + 14
            leftMargin: 14
            rightMargin: 14
            bottomMargin: 14
        }
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: "Night Light"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleLarge
                font.weight: Typography.weight.bold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.statusText
                color: HyprsunsetService.available
                    ? Colors.onSurfaceVariant
                    : Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }
        }

        // Blue-light filter row, styled like the settings rows.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: filterRow.implicitHeight + 24
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

            RowLayout {
                id: filterRow

                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter
                    radius: Dimensions.radius.small + 2
                    color: HyprsunsetService.enabled
                        ? Colors.primaryContainer
                        : Colors.surfaceContainerHighest

                    Behavior on color { ColorAnimation { duration: Motion.color } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.nightlight
                        color: HyprsunsetService.enabled
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
                        text: "Blue-light filter"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyMedium
                        font.weight: Typography.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Warm the display in the evening"
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }
                }

                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    checked: HyprsunsetService.enabled
                    interactive: HyprsunsetService.available
                    onToggled: checked => HyprsunsetService.setEnabledManual(checked)
                }
            }
        }

        TemperatureCard {
            id: temperatureCard

            temperature: HyprsunsetService.temperature
            minTemperature: HyprsunsetService.minTemperature
            maxTemperature: HyprsunsetService.maxTemperature
            interactive: HyprsunsetService.available
            onTemperatureRequested: kelvin => HyprsunsetService.setTemperature(kelvin)
        }

        ScheduleCard {
        }
    }
}
