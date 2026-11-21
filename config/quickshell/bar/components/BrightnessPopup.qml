import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components"
import "../../theme"
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

    readonly property string scheduleWarning: {
        if (HyprsunsetService.scheduleValid)
            return "";

        if (HyprsunsetService.scheduleMode === "sun") {
            if (HyprsunsetService.locationRefreshing)
                return "";
            if (!HyprsunsetService.locationAvailable)
                return "Location unavailable — refresh or use fixed times";
            return "Sunrise/sunset unavailable for this date";
        }

        return "On and off times must differ";
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: scheduleColumn.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: HyprsunsetService.scheduleActive
                    ? Colors.withAlpha(Colors.primary, 0.35)
                    : Colors.withAlpha(Colors.outlineVariant, 0.22)

                Behavior on border.color { ColorAnimation { duration: 140 } }

                ColumnLayout {
                    id: scheduleColumn

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignVCenter
                            radius: Dimensions.radius.small
                            color: HyprsunsetService.scheduleActive
                                ? Colors.primaryContainer
                                : Colors.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: Icons.schedule
                                color: HyprsunsetService.scheduleActive
                                    ? Colors.onPrimaryContainer
                                    : Colors.onSurfaceVariant
                                font.family: Typography.iconFont
                                font.pixelSize: Dimensions.icon.medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: "Automatic schedule"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: Typography.weight.bold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: HyprsunsetService.scheduleStatusText
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            checked: HyprsunsetService.autoSchedule
                            interactive: HyprsunsetService.available
                                && HyprsunsetService.scheduleValid
                            onToggled: checked => HyprsunsetService.setScheduleEnabled(checked)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ModeChip {
                            Layout.fillWidth: true
                            text: "Fixed times"
                            active: HyprsunsetService.scheduleMode === "fixed"
                            onClicked: HyprsunsetService.setScheduleMode("fixed")
                        }

                        ModeChip {
                            Layout.fillWidth: true
                            text: "Sunrise / sunset"
                            active: HyprsunsetService.scheduleMode === "sun"
                            onClicked: HyprsunsetService.setScheduleMode("sun")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: HyprsunsetService.scheduleMode === "fixed"

                        TimeField {
                            Layout.fillWidth: true
                            label: "Turn on"
                            hour: HyprsunsetService.onHour
                            minute: HyprsunsetService.onMinute
                            interactive: HyprsunsetService.available
                            onEdited: (hour, minute) => HyprsunsetService.setOnTime(hour, minute)
                        }

                        TimeField {
                            Layout.fillWidth: true
                            label: "Turn off"
                            hour: HyprsunsetService.offHour
                            minute: HyprsunsetService.offMinute
                            interactive: HyprsunsetService.available
                            onEdited: (hour, minute) => HyprsunsetService.setOffTime(hour, minute)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: HyprsunsetService.scheduleMode === "sun"

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

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: "Location"
                                    color: Colors.onSurfaceVariant
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelSmall
                                    font.weight: Typography.weight.medium
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: HyprsunsetService.locationLabel
                                    color: HyprsunsetService.locationAvailable
                                        ? Colors.onSurface
                                        : Colors.onSurfaceVariant
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelMedium
                                    elide: Text.ElideRight
                                }
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
                                caption: "Sunrise"
                                value: HyprsunsetService.sunriseLabel
                            }

                            SunTimeCard {
                                Layout.fillWidth: true
                                icon: Icons.darkMode
                                caption: "Sunset"
                                value: HyprsunsetService.sunsetLabel
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.scheduleWarning !== ""
                        text: root.scheduleWarning
                        color: Colors.error
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

    component StepButton: Item {
        id: stepButton

        property string icon: ""
        property bool interactive: true

        signal clicked()

        width: 30
        height: 18
        opacity: stepButton.interactive ? 1.0 : 0.35

        Text {
            anchors.centerIn: parent
            text: stepButton.icon
            color: stepMouse.containsMouse
                ? Colors.primary
                : Colors.onSurfaceVariant
            font.family: Typography.iconFont
            font.pixelSize: Dimensions.icon.large

            Behavior on color { ColorAnimation { duration: 100 } }
        }

        MouseArea {
            id: stepMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: stepButton.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: stepButton.clicked()
        }
    }

    component TimeColumn: Item {
        id: timeColumn

        property int value: 0
        property bool interactive: true

        signal step(int delta)

        width: 36
        height: 60

        Column {
            anchors.centerIn: parent
            spacing: 0

            StepButton {
                icon: Icons.chevronUp
                interactive: timeColumn.interactive
                onClicked: timeColumn.step(1)
            }

            Text {
                width: parent.width
                height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: timeColumn.value < 10 ? "0" + timeColumn.value : String(timeColumn.value)
                color: timeColumn.interactive ? Colors.onSurface : Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.titleSmall
                font.weight: Typography.weight.bold
            }

            StepButton {
                icon: Icons.chevronDown
                interactive: timeColumn.interactive
                onClicked: timeColumn.step(-1)
            }
        }

        WheelHandler {
            enabled: timeColumn.interactive
            onWheel: wheel => {
                if (wheel.angleDelta.y === 0)
                    return;

                timeColumn.step(wheel.angleDelta.y > 0 ? 1 : -1);
                wheel.accepted = true;
            }
        }
    }

    component ModeChip: Rectangle {
        id: modeChip

        property string text: ""
        property bool active: false

        signal clicked()

        readonly property bool hovered: modeMouse.containsMouse

        implicitHeight: 26
        radius: Dimensions.radius.full
        color: modeChip.active
            ? Colors.primaryContainer
            : modeChip.hovered
                ? Colors.stateLayer(Colors.primary, 0.12)
                : Colors.surfaceContainerLowest
        border.width: 1
        border.color: modeChip.active
            ? Colors.withAlpha(Colors.primary, 0.7)
            : Colors.withAlpha(Colors.outlineVariant, 0.35)

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: modeChip.text
            color: modeChip.active ? Colors.onPrimaryContainer : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: modeChip.active ? Typography.weight.bold : Typography.weight.medium
        }

        MouseArea {
            id: modeMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: HyprsunsetService.available
            cursorShape: Qt.PointingHandCursor
            onClicked: modeChip.clicked()
        }
    }


    component TimeField: Item {
        id: timeField

        property string label: ""
        property int hour: 0
        property int minute: 0
        property bool interactive: true

        signal edited(int hour, int minute)

        implicitWidth: 150
        implicitHeight: 96

        function applyTotal(total) {
            const wrapped = ((total % 1440) + 1440) % 1440;
            timeField.edited(Math.floor(wrapped / 60), wrapped % 60);
        }

        function stepHour(delta) {
            timeField.applyTotal(timeField.hour * 60 + timeField.minute + delta * 60);
        }

        function stepMinute(delta) {
            timeField.applyTotal(timeField.hour * 60 + timeField.minute + delta * 5);
        }

        Rectangle {
            anchors.fill: parent
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: timeHover.hovered
                ? Colors.withAlpha(Colors.primary, 0.35)
                : Colors.withAlpha(Colors.outlineVariant, 0.3)

            Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        HoverHandler {
            id: timeHover
            enabled: timeField.interactive
        }

        Column {
            anchors {
                fill: parent
                margins: 8
            }
            spacing: 2

            Text {
                width: parent.width
                text: timeField.label
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                font.weight: Typography.weight.medium
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                TimeColumn {
                    value: timeField.hour
                    interactive: timeField.interactive
                    onStep: delta => timeField.stepHour(delta)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ":"
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.titleSmall
                    font.weight: Typography.weight.bold
                }

                TimeColumn {
                    value: timeField.minute
                    interactive: timeField.interactive
                    onStep: delta => timeField.stepMinute(delta)
                }
            }
        }

    }


}
