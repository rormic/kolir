pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../theme"
import ".."

// Connection form for a selected Wi-Fi password or for a hidden network.
// Both modes share one card and one set of fields; the page owns the nmcli
// processes and decides which submit routine to run.
Rectangle {
    id: root

    property string mode: "" // "password", "hidden"
    property string ssid: ""
    property bool showPassword: false
    property bool busy: false
    property string error: ""
    property int securityIndex: 1

    signal passwordEdited(string password)
    signal ssidEdited(string ssid)
    signal showPasswordToggled()
    signal securityIndexSelected(int index)
    signal submitRequested()
    signal cancelRequested()

    readonly property bool secretVisible: root.mode === "password"
        || root.securityIndex === 1

    onModeChanged: passwordField.text = ""

    Layout.fillWidth: true
    implicitHeight: formColumn.implicitHeight + 24
    radius: Dimensions.radius.medium
    color: Colors.surfaceContainerHigh
    border.width: 1
    border.color: Colors.withAlpha(Colors.primary, 0.35)

    ColumnLayout {
        id: formColumn
        anchors { fill: parent; margins: 12 }
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.mode === "password"
                ? "Connect to: " + root.ssid
                : "Hidden network"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.bodyMedium
            font.weight: Typography.weight.medium
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            visible: root.mode === "hidden"
            radius: Dimensions.radius.small
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.4)

            TextInput {
                id: hiddenSsidInput

                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                color: Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.bodyMedium
                clip: true
                selectByMouse: true
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.ssidEdited(text)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !hiddenSsidInput.text && !hiddenSsidInput.activeFocus
                    text: "SSID"
                    color: Colors.onSurfaceVariant
                    font: hiddenSsidInput.font
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.mode === "hidden"

            Repeater {
                model: ["Open", "WPA/WPA2"]

                delegate: Rectangle {
                    id: securityChip

                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: Dimensions.radius.full
                    color: root.securityIndex === securityChip.index
                        ? Colors.primaryContainer : Colors.surfaceContainerLowest
                    border.width: 1
                    border.color: root.securityIndex === securityChip.index
                        ? Colors.withAlpha(Colors.primary, 0.6)
                        : Colors.withAlpha(Colors.outlineVariant, 0.4)

                    Text {
                        anchors.centerIn: parent
                        text: securityChip.modelData
                        color: root.securityIndex === securityChip.index
                            ? Colors.onPrimaryContainer : Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.securityIndexSelected(securityChip.index)
                    }
                }
            }
        }

        PasswordField {
            id: passwordField

            visible: root.secretVisible
            placeholder: root.mode === "hidden" ? "Password" : ""
            showPassword: root.showPassword
            onTextChanged: root.passwordEdited(text)
            onVisibilityToggled: root.showPasswordToggled()
            onSubmitRequested: root.submitRequested()
            onCancelRequested: root.cancelRequested()
        }

        Text {
            visible: root.error !== ""
            Layout.fillWidth: true
            text: root.error
            color: Colors.error
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Rectangle {
                Layout.preferredWidth: cancelText.implicitWidth + 20
                Layout.preferredHeight: 30
                radius: Dimensions.radius.full
                color: "transparent"
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.4)

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelRequested()
                }
            }

            Rectangle {
                Layout.preferredWidth: connectText.implicitWidth + 20
                Layout.preferredHeight: 30
                radius: Dimensions.radius.full
                color: Colors.primary
                opacity: (root.busy || (root.mode === "hidden" && !root.ssid)) ? 0.7 : 1.0

                Text {
                    id: connectText

                    anchors.centerIn: parent
                    text: root.busy ? "Connecting…" : "Connect"
                    color: Colors.onPrimary
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelMedium
                    font.weight: Typography.weight.medium
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.busy && (root.mode !== "hidden" || !!root.ssid)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submitRequested()
                }
            }
        }
    }
}
