import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components"
import "../../theme"
import "../../services"
import "nightLight"

// Night-light popup for the brightness pill. Right click opens it; the
// hyprsunset IPC is owned by HyprsunsetService.
AnchoredPopup {
    id: root

    panelWidth: 380
    panelHeight: 500
    headerHeight: 52

    readonly property string statusText: {
        if (!HyprsunsetService.available)
            return "hyprsunset is not running";

        const state = HyprsunsetService.enabled ? "On" : "Off";
        let text = state + " · " + HyprsunsetService.temperature + " K";

        if (HyprsunsetService.scheduleActive && HyprsunsetService.scheduleLabel !== "")
            text += " · " + HyprsunsetService.scheduleLabel;

        return text;
    }

    onOpened: {
        HyprsunsetService.refresh();
        if (HyprsunsetService.sunMode)
            HyprsunsetService.refreshLocation(false);
    }

    onHidden: temperatureCard.cancelDrag()

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

    headerContent: [
        Text {
            id: headerIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: Icons.nightlight
            color: Colors.tertiary
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.extraLarge
        },

        Column {
            anchors {
                left: headerIcon.right
                leftMargin: 10
                right: closeButton.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            spacing: 1

            Text {
                width: parent.width
                text: "Night Light"
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.bold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.statusText
                color: HyprsunsetService.available
                    ? Colors.onSurfaceVariant
                    : Colors.error
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                elide: Text.ElideRight
            }
        },

        IconButton {
            id: closeButton

            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            icon: Icons.close
            iconSize: Dimensions.icon.medium
            onClicked: root.close()
        }
    ]

    ColumnLayout {
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: "Blue-light filter"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelLarge
                        font.weight: Typography.weight.medium
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

            TemperatureCard {
                id: temperatureCard

                temperature: HyprsunsetService.temperature
                minTemperature: HyprsunsetService.minTemperature
                maxTemperature: HyprsunsetService.maxTemperature
                interactive: HyprsunsetService.available
                onTemperatureRequested: kelvin => HyprsunsetService.setTemperature(kelvin)
            }

            ScheduleCard {
                id: scheduleCard
            }
        }
}
