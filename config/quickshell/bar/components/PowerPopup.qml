pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services"
import "../../theme"

// Session power sheet for the bar's power button. It uses the same
// EmbeddedSheet as the other right-edge sheets; only the action grid and the
// confirmation view live here. PowerService owns the commands, so a failure
// keeps the sheet open with the error in the header.
EmbeddedSheet {
    id: root

    mirror: true

    // Geometry mirrors the content layout below. Five actions fit without a
    // scroll, and the confirmation view swaps into the same body, so the panel
    // never changes height.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 12
    readonly property int contentBottomReserve: 6
    readonly property int tileHeight: 76
    readonly property int shutdownHeight: 52
    readonly property int tileSpacing: 8
    readonly property int confirmTimeout: 6000

    readonly property int actionsHeight: 2 * root.tileHeight
        + root.tileSpacing + root.contentColumnSpacing + root.shutdownHeight

    panelHeight: root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + root.actionsHeight + root.contentBottomReserve

    // The five core actions. Lock and suspend run at once; the three that end
    // the session ask for confirmation first.
    readonly property var actions: [
        {
            id: "lock",
            icon: Icons.lock,
            label: "Lock",
            destructive: false,
            confirm: false,
            question: "",
            detail: ""
        },
        {
            id: "suspend",
            icon: Icons.suspend,
            label: "Suspend",
            destructive: false,
            confirm: false,
            question: "",
            detail: ""
        },
        {
            id: "logout",
            icon: Icons.logout,
            label: "Log out",
            destructive: true,
            confirm: true,
            question: "Log out?",
            detail: "All apps will close."
        },
        {
            id: "reboot",
            icon: Icons.restart,
            label: "Restart",
            destructive: true,
            confirm: true,
            question: "Restart?",
            detail: "The computer will restart."
        },
        {
            id: "poweroff",
            icon: Icons.power,
            label: "Shut down",
            destructive: true,
            confirm: true,
            question: "Shut down?",
            detail: "All apps will close."
        }
    ]

    // Empty while the action grid is showing; the action id while the
    // confirmation view is up.
    property string confirming: ""
    property string confirmIcon: ""
    property string confirmLabel: ""
    property string confirmTitle: ""
    property string confirmSubtitle: ""

    function open() {
        if (root.opened)
            return;

        root.confirming = "";
        confirmTimer.stop();
        root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        root.revealClose();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    function actionById(id) {
        for (let i = 0; i < root.actions.length; i++) {
            if (root.actions[i].id === id)
                return root.actions[i];
        }

        return null;
    }

    function requestAction(action) {
        if (!action || PowerService.busy)
            return;

        if (!action.confirm) {
            root.runAction(action);
            return;
        }

        root.confirmIcon = action.icon;
        root.confirmLabel = action.label;
        root.confirmTitle = action.question;
        root.confirmSubtitle = action.detail;
        root.confirming = action.id;
        root.forceActiveFocus();
        confirmTimer.restart();
    }

    function cancelConfirm() {
        confirmTimer.stop();
        root.confirming = "";
        root.forceActiveFocus();
    }

    function runAction(action) {
        if (!action || PowerService.busy)
            return;

        confirmTimer.stop();

        if (action.id === "lock")
            PowerService.lock();
        else if (action.id === "suspend")
            PowerService.suspend();
        else if (action.id === "logout")
            PowerService.logout();
        else if (action.id === "reboot")
            PowerService.reboot();
        else if (action.id === "poweroff")
            PowerService.poweroff();
    }

    function confirmAction() {
        const action = root.actionById(root.confirming);
        if (action)
            root.runAction(action);
    }

    onDismissalRequested: root.close()

    onDidClose: {
        confirmTimer.stop();
        root.confirming = "";
    }

    Keys.onEscapePressed: function (event) {
        if (root.confirming !== "") {
            root.cancelConfirm();
        } else {
            root.close();
        }

        event.accepted = true;
    }

    Timer {
        id: confirmTimer

        interval: root.confirmTimeout
        repeat: false
        running: root.confirming !== "" && !PowerService.busy
        onTriggered: root.cancelConfirm()
    }

    Connections {
        target: PowerService

        function onFinished(action) {
            if (root.opened)
                root.close();
        }
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function lock(): void {
            PowerService.lock();
        }

        function suspend(): void {
            PowerService.suspend();
        }

        function logout(): void {
            PowerService.logout();
        }

        function reboot(): void {
            PowerService.reboot();
        }

        function poweroff(): void {
            PowerService.poweroff();
        }

        function status(): string {
            return JSON.stringify({
                open: root.opened,
                modal: root.modal,
                busy: PowerService.busy,
                action: PowerService.activeAction,
                confirming: root.confirming,
                lastError: PowerService.lastError
            });
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + root.contentColumnMargins
            leftMargin: root.contentColumnMargins
            rightMargin: root.contentColumnMargins
            bottomMargin: root.contentColumnMargins
        }
        spacing: root.contentColumnSpacing

        PopupHeader {
            Layout.fillWidth: true
            Layout.preferredHeight: root.titleBlockHeight
            title: "Power"
            subtitle: PowerService.lastError !== ""
                ? PowerService.lastError
                : (PowerService.busy
                    ? "Working…"
                    : "Lock, suspend or end the session")
            subtitleColor: PowerService.lastError !== ""
                ? Colors.error
                : Colors.onSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                id: gridColumn

                anchors.fill: parent
                spacing: root.contentColumnSpacing
                visible: root.confirming === ""

                Grid {
                    id: grid

                    width: parent.width
                    columns: 2
                    columnSpacing: root.tileSpacing
                    rowSpacing: root.tileSpacing

                    Repeater {
                        model: root.actions.slice(0, 4)

                        delegate: PowerTile {
                            required property var modelData

                            width: (grid.width - grid.columnSpacing) / 2
                            height: root.tileHeight
                            icon: modelData.icon
                            label: modelData.label
                            destructive: modelData.destructive
                            enabled: !PowerService.busy
                            onActivated: root.requestAction(modelData)
                        }
                    }
                }

                PowerTile {
                    width: parent.width
                    height: root.shutdownHeight
                    fullWidth: true
                    icon: root.actions[4].icon
                    label: root.actions[4].label
                    destructive: true
                    enabled: !PowerService.busy
                    onActivated: root.requestAction(root.actions[4])
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 10
                visible: root.confirming !== ""

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.confirmIcon
                    color: Colors.error
                    font.family: Typography.iconFont
                    font.pixelSize: 36
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.confirmTitle
                    color: Colors.onSurface
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.titleLarge
                    font.weight: Typography.weight.bold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.confirmSubtitle
                    color: Colors.onSurfaceVariant
                    font.family: Typography.barFont
                    font.pixelSize: Typography.size.labelSmall
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Pill {
                        height: 34
                        opacity: PowerService.busy ? 0.6 : 1.0
                        text: "Cancel"
                        textSize: Typography.size.labelMedium
                        textWeight: Typography.weight.medium
                        horizontalPadding: 16

                        MouseArea {
                            anchors.fill: parent
                            enabled: !PowerService.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelConfirm()
                        }
                    }

                    Pill {
                        height: 34
                        opacity: PowerService.busy ? 0.6 : 1.0
                        text: root.confirmLabel
                        textSize: Typography.size.labelMedium
                        textWeight: Typography.weight.medium
                        textColor: Colors.onErrorContainer
                        surfaceColor: Colors.errorContainer
                        borderColor: Colors.withAlpha(Colors.error, 0.45)
                        horizontalPadding: 16

                        MouseArea {
                            anchors.fill: parent
                            enabled: !PowerService.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmAction()
                        }
                    }
                }
            }
        }
    }
}
