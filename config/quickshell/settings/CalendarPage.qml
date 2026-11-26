import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../services"
import "../theme"
import "../bar/components"

// Google Calendar page of the settings popout.
//
// It owns only the OAuth client credentials (pasted once) and the account
// actions; everything else lives behind CalendarService → CalendarGoogleBackend
// → scripts/google-calendar/main.py. The helper is the only component that
// talks to Google, so this page never builds a request or holds a token.
//
// The credentials card stays visible in both states on purpose: re-pasting a
// client ID/secret and pressing "Reconnect" is the recovery path after a
// revoked token, and keeping the card in place means the sheet never changes
// height when the account connects or disconnects.
Item {
    id: root

    signal back()

    property int topInset: 0

    implicitWidth: 380
    // Derived from the cards so it can never drift from the rendered content:
    // header, the body margins and the ColumnLayout's own implicit height.
    // SettingsMenu mirrors the largest state in `calendarHeight`.
    implicitHeight: root.topInset + header.height + 14 + body.implicitHeight + 14

    property bool authRunning: false
    property string authError: ""
    property string authMessage: ""

    readonly property bool connected: CalendarService.googleConnected
    readonly property bool syncing: CalendarService.googleSyncing
    readonly property bool needsReauth: CalendarService.googleNeedsReauth
    readonly property int calendarCount: CalendarService.googleCalendarCount

    readonly property string accountTitle: CalendarService.googleAccount !== ""
        ? CalendarService.googleAccount : "Google Calendar"

    readonly property string accountSubtitle: {
        if (root.authRunning)
            return "Waiting for Google in your browser…";
        if (root.connected && root.syncing)
            return "Syncing events…";
        if (root.connected) {
            const count = root.calendarCount;
            const calendars = count === 1 ? "1 calendar" : count + " calendars";
            return calendars + " · " + root.lastSyncLabel();
        }
        if (root.needsReauth)
            return "Calendar access missing — connect again";
        return "Not connected · events stay on this machine";
    }

    // Kept as a function rather than a binding so the label is rebuilt when
    // the page becomes visible instead of every second.
    function lastSyncLabel() {
        const seconds = CalendarService.googleLastSync;
        if (!seconds)
            return "not synced yet";
        const date = new Date(seconds * 1000);
        const today = new Date();
        const sameDay = date.toDateString() === today.toDateString();
        return "synced " + Qt.formatDateTime(date,
            sameDay ? "HH:mm" : "d MMM HH:mm");
    }

    function parse(raw) {
        const text = String(raw || "").trim();
        if (text === "")
            return null;
        try {
            const data = JSON.parse(text);
            return data && typeof data === "object" ? data : null;
        } catch (error) {
            console.warn("CalendarPage: invalid auth output:", error);
            return null;
        }
    }

    function startAuth() {
        if (root.authRunning)
            return;

        const clientId = clientIdField.text.trim();
        const clientSecret = secretField.text.trim();

        root.authMessage = "";
        if (clientId === "") {
            root.authError = "Paste the OAuth client ID first";
            clientIdField.forceFocus();
            return;
        }
        // The secret is only needed the first time: the helper reuses the one
        // stored with the refresh token for a later reconnect.
        if (clientSecret === "" && !CalendarService.googleHasSecret) {
            root.authError = "Paste the OAuth client secret too";
            secretField.forceFocus();
            return;
        }

        root.authError = "";
        root.authMessage = "Finish the sign-in in your browser";
        root.authRunning = true;
        // The secret travels in the environment (readable only by this user),
        // never in argv, so it cannot be seen in `ps` while the browser flow
        // waits.
        authProc.environment = {
            "KOLIR_GOOGLE_CLIENT_SECRET": clientSecret,
        };
        authProc.command = [
            "python3", ShellPaths.googleCalendarScript, "auth",
            "--client-id", clientId,
            "--timeout", "300",
        ];
        authProc.running = true;
    }

    function finishAuth(raw) {
        const data = root.parse(raw);
        if (!data || data.ok !== true) {
            root.authError = (data && data.error) || "Google authorization failed";
            return;
        }

        root.authError = "";
        root.authMessage = "Connected as " + (data.account || "Google");
        secretField.text = "";
        // The backend re-reads the state file (`status`) and then syncs.
        CalendarService.refresh();
    }

    function disconnect() {
        root.authMessage = "";
        root.authError = "";
        CalendarService.disconnectGoogle();
    }

    // A fresh open shows the stored client ID and clears a stale result line,
    // but never interrupts a running authorization.
    onVisibleChanged: {
        if (!root.visible || root.authRunning)
            return;
        clientIdField.text = CalendarService.googleClientId;
        root.authError = "";
        root.authMessage = "";
    }

    Component.onCompleted: {
        clientIdField.text = CalendarService.googleClientId;
    }

    // The first `status` answer usually lands after this page was created (all
    // settings pages exist from the start), so fill the field once it knows
    // the stored client ID — unless the user is already typing.
    Connections {
        target: CalendarService

        function onGoogleClientIdChanged() {
            if (!root.authRunning && clientIdField.text === "")
                clientIdField.text = CalendarService.googleClientId;
        }
    }

    Process {
        id: authProc

        command: []
        property bool handled: false

        onStarted: authProc.handled = false

        stdout: StdioCollector {
            onStreamFinished: {
                authProc.handled = true;
                root.finishAuth(text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.authRunning = false;
            if (!authProc.handled)
                root.finishAuth("");
        }
    }

    // ── Reusable text action ───────────────────────────────────────────────
    component TextAction: Rectangle {
        id: action

        property string label: ""
        property string icon: ""
        property bool destructive: false
        property bool busy: false

        signal activated()

        readonly property bool hovered: actionMouse.containsMouse

        implicitWidth: actionRow.implicitWidth + 20
        implicitHeight: 24
        radius: height / 2
        color: "transparent"

        StateLayer {
            shown: action.hovered
            tint: action.destructive ? Colors.error : Colors.primary
            strength: 0.12
        }

        Row {
            id: actionRow

            anchors.centerIn: parent
            spacing: 4

            Text {
                id: actionIcon

                anchors.verticalCenter: parent.verticalCenter
                visible: action.icon !== ""
                text: action.icon
                color: action.destructive
                    ? (action.hovered ? Colors.error : Colors.onSurfaceVariant)
                    : Colors.primary
                font.family: Typography.iconFont
                font.pixelSize: Dimensions.icon.small + 2

                RotationAnimation {
                    target: actionIcon
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: action.busy
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: action.label
                color: action.destructive
                    ? (action.hovered ? Colors.error : Colors.onSurfaceVariant)
                    : Colors.primary
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
                font.weight: Typography.weight.medium
            }
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.activated()
        }
    }

    // ── Reusable filled action ─────────────────────────────────────────────
    component FilledAction: Rectangle {
        id: action

        property string label: ""
        property bool enabledByOwner: true

        signal activated()

        readonly property bool hovered: actionMouse.containsMouse
            && action.enabledByOwner

        implicitWidth: actionLabel.implicitWidth + 28
        implicitHeight: 30
        radius: height / 2
        color: action.enabledByOwner ? Colors.primary : Colors.surfaceContainerHighest

        StateLayer {
            shown: action.hovered
            tint: Colors.onPrimary
            strength: 0.12
        }

        Text {
            id: actionLabel

            anchors.centerIn: parent
            text: action.label
            color: action.enabledByOwner
                ? Colors.onPrimary : Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.semibold
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: action.enabledByOwner
            cursorShape: action.enabledByOwner
                ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: action.activated()
        }
    }

    // ── Header ─────────────────────────────────────────────────────────────
    SettingsPageHeader {
        id: header

        topInset: root.topInset
        title: "Calendar"
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

            // ── Account ────────────────────────────────────────────────────
            Rectangle {
                id: accountCard

                Layout.fillWidth: true
                implicitHeight: accountContent.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: root.connected
                    ? Colors.withAlpha(Colors.primary, 0.35)
                    : Colors.withAlpha(Colors.outlineVariant, 0.22)

                Behavior on border.color {
                    ColorAnimation { duration: Motion.hover }
                }

                ColumnLayout {
                    id: accountContent

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            Layout.alignment: Qt.AlignVCenter
                            radius: Dimensions.radius.small + 2
                            color: root.connected
                                ? Colors.primaryContainer
                                : Colors.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: root.connected ? Icons.cloudDone : Icons.calendar
                                color: root.connected
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
                                text: root.accountTitle
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: Typography.weight.medium
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.accountSubtitle
                                color: root.needsReauth
                                    ? Colors.error
                                    : root.connected
                                        ? Colors.primary
                                        : Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideRight
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        visible: root.connected
                        spacing: 8

                        TextAction {
                            Layout.alignment: Qt.AlignVCenter
                            label: "Sync now"
                            icon: Icons.refresh
                            busy: root.syncing
                            onActivated: CalendarService.refresh(true)
                        }

                        // Background failure (a revoked token, a missing
                        // permission, the network). The sheet repeats it in
                        // red under the day list; here it sits next to the
                        // account so a failed sync is visible without opening
                        // the calendar.
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            visible: text !== ""
                            text: CalendarService.lastError
                            color: Colors.error
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }

                        Item {
                            Layout.fillWidth: true
                            visible: CalendarService.lastError === ""
                        }

                        TextAction {
                            Layout.alignment: Qt.AlignVCenter
                            label: "Disconnect"
                            icon: Icons.linkOff
                            destructive: true
                            onActivated: root.disconnect()
                        }
                    }
                }
            }

            // ── OAuth client ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: clientContent.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: clientContent

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: "OAuth client"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Create an OAuth client of type “Desktop app” in "
                            + "Google Cloud Console and paste its ID and secret here. "
                            + "Both are stored with the refresh token in "
                            + "~/.cache/quickshell/google-calendar.json (0600); a later "
                            + "reconnect can reuse the stored secret."
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                    }

                    TextField {
                        id: clientIdField

                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        placeholder: "Client ID (…apps.googleusercontent.com)"
                        onTextChanged: root.authError = ""
                        onAccepted: root.startAuth()
                    }

                    PasswordField {
                        id: secretField

                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        placeholder: CalendarService.googleHasSecret
                            ? "Client secret (stored — leave empty to reuse)"
                            : "Client secret"

                        onTextChanged: root.authError = ""
                        onVisibilityToggled: showPassword = !showPassword
                        onSubmitRequested: root.startAuth()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        spacing: 10

                        FilledAction {
                            Layout.alignment: Qt.AlignVCenter
                            label: root.authRunning
                                ? "Waiting for Google…"
                                : root.connected ? "Reconnect" : "Connect with Google"
                            enabledByOwner: !root.authRunning
                            onActivated: root.startAuth()
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.authMessage
                            color: Colors.primary
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }

                    // Consent failures need the whole instruction ("leave both
                    // calendar permissions checked"), so they wrap on their own
                    // line instead of eliding next to the button.
                    Text {
                        Layout.fillWidth: true
                        visible: root.authError !== ""
                        text: root.authError
                        color: Colors.error
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                    }
                }
            }

            // ── What syncs, and what it never does ─────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: helpContent.implicitHeight + 24
                radius: Dimensions.radius.medium
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

                ColumnLayout {
                    id: helpContent

                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: "Read and add only"
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        font.weight: Typography.weight.bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Events from every calendar in the account are read "
                            + "into the sheet. Google rows are read-only: they carry "
                            + "no delete button, and the helper never calls update "
                            + "or delete. New events go to the primary calendar; "
                            + "events created before connecting stay local and "
                            + "editable."
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text: "Google Cloud setup: enable the Google Calendar API, "
                            + "add your account as a test user on the OAuth consent "
                            + "screen, then create the Desktop app client. Scopes: "
                            + "calendar.events and calendar.calendarlist.readonly."
                        color: Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                    }
                }
            }
        }
    }
}
