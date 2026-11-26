import QtQuick
import Quickshell.Io
import ".."
import "CalendarModel.js" as Model

// Google Calendar storage for CalendarService.
//
// It is a hybrid backend: the local JSON file keeps the events created while
// no account is connected (and every event that was here before), while the
// Google helper adds the account's calendars to the same snapshot. That is why
// this file names itself "google" only while a refresh token is present and
// "local" otherwise.
//
// The helper (scripts/google-calendar/main.py) is the only writer of
// ~/.cache/quickshell/google-calendar.json and the only component that talks
// to Google. The flow is:
//
//   load()    local.load() + `status` (cached account, calendars and events)
//   refresh() `sync` (network, at most one at a time) — the sheet, the 5 minute
//             timer, the settings page and the IPC all call this
//   create()  Google account: optimistic `pending` row, then `add`; local
//             otherwise (so the calendar still works offline and unconfigured)
//   update()  local events only
//   remove()  local events only — Google is read-plus-add, never delete
//
// Google events carry `readOnly: true`, `calendarId`, `calendarSummary` and
// `calendarColor`, so the sheet can hide the trash button, name the source and
// tint the row accent. They also carry the helper's `pending` flag until the
// insert response replaces the optimistic row.
//
// Nothing here is persisted by QML: the helper owns the state file, so a shell
// restart paints the cached snapshot instantly and then refreshes.
QtObject {
    id: root

    readonly property string provider: root.connected ? "google" : "local"

    property bool ready: false
    property bool configured: false
    property bool hasSecret: false
    property bool connected: false
    property bool needsReauth: false
    property bool syncing: false

    property string account: ""
    property string clientId: ""
    property real lastSync: 0
    property int calendarCount: 0
    property string lastError: ""

    property var events: []
    property var remoteEvents: []
    property var localEvents: []

    signal loaded(var events)
    signal changed(var events)
    signal failed(string message)

    // The helper writes this file; QML only reads it through `status`.
    readonly property string statePath: ShellPaths.googleCalendarState
    readonly property string helper: ShellPaths.googleCalendarScript

    // One keepalive sync every five minutes. Paused after a revoked token
    // until the user reconnects, so a dead token cannot hammer the network.
    property Timer syncTimer: Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: root.connected && !root.needsReauth
        onTriggered: root.refresh()
    }

    // ── Local half ─────────────────────────────────────────────────────────
    property var local: CalendarLocalBackend {}

    property Connections localSignals: Connections {
        target: root.local

        function onLoaded(list) {
            root.localEvents = list;
            root.publish();
        }

        function onChanged(list) {
            root.localEvents = list;
            root.publish();
        }

        function onFailed(message) {
            root.report(message);
        }
    }

    // ── Snapshot ───────────────────────────────────────────────────────────
    // Both halves share the same canonical shape, so the merged list is just
    // normalised and re-sorted. Local events have no `readOnly`, which is what
    // keeps them editable.
    function publish() {
        root.events = Model.normalizeList(
            root.localEvents.concat(root.remoteEvents));
        if (root.ready)
            root.changed(root.events);
        else {
            root.ready = true;
            root.loaded(root.events);
        }
    }

    function findEvent(uid) {
        const wanted = String(uid);
        for (const item of root.events) {
            if (item.uid === wanted)
                return item;
        }
        return null;
    }

    function report(message) {
        const text = String(message === undefined || message === null ? "" : message);
        root.lastError = text;
        if (text !== "" && text !== root.lastEmittedError) {
            root.lastEmittedError = text;
            root.failed(text);
        } else if (text === "") {
            root.lastEmittedError = "";
        }
    }

    function clearError() {
        root.lastError = "";
        root.lastEmittedError = "";
    }

    // Set while the same message is on screen, so a five-minute retry of a
    // failing request does not log once per tick.
    property string lastEmittedError: ""

    function parse(raw) {
        const text = String(raw || "").trim();
        if (text === "")
            return null;
        try {
            const data = JSON.parse(text);
            return data && typeof data === "object" ? data : null;
        } catch (error) {
            console.warn("CalendarGoogleBackend: invalid helper output:", error);
            return null;
        }
    }

    // ── Backend contract ───────────────────────────────────────────────────
    function load() {
        root.local.load();
        root.runStatus();
    }

    // Refresh the cached state and then hit the network. Called by the timer,
    // CalendarService.refresh() (sheet open), the settings page and the IPC.
    // A non-forced call is skipped when the last attempt is younger than
    // `refreshFloor`, so opening the sheet repeatedly cannot poll Google.
    readonly property int refreshFloor: 60
    property real lastAttempt: 0

    function refresh(force) {
        if (root.statusProcess.running || root.syncProcess.running)
            return;

        if (root.connected && !root.needsReauth) {
            if (!force && Date.now() / 1000 - root.lastAttempt < root.refreshFloor)
                return;
            root.startSync();
        } else {
            root.runStatus();
        }
    }

    function create(event) {
        if (!event)
            return;

        if (!root.connected) {
            root.local.create(event);
            return;
        }

        // Paint the row now and reconcile with Google's response, so a slow
        // request never leaves the form closed with nothing on the screen.
        const pending = Object.assign({}, event, {
            readOnly: true,
            pending: true,
        });
        root.remoteEvents = root.remoteEvents.concat([pending]);
        root.addQueue = root.addQueue.concat([{
            event: event,
            pendingUid: event.uid,
        }]);
        root.publish();
        root.pumpAdd();
    }

    function update(event) {
        if (!event)
            return;
        if (event.readOnly === true) {
            root.report("Google Calendar events are read-only");
            return;
        }
        root.local.update(event);
    }

    function remove(uid) {
        const target = root.findEvent(uid);
        if (target && target.readOnly === true) {
            root.report("Google Calendar events are read-only");
            return;
        }
        root.local.remove(uid);
    }

    // ── status ─────────────────────────────────────────────────────────────
    function runStatus() {
        if (root.statusProcess.running)
            return;
        root.statusProcess.running = true;
    }

    property Process statusProcess: Process {
        id: statusProc

        command: ["python3", root.helper, "--state", root.statePath, "status"]

        property bool handled: false

        onStarted: statusProc.handled = false

        stdout: StdioCollector {
            onStreamFinished: {
                statusProc.handled = true;
                root.applyStatus(text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!statusProc.handled)
                root.applyStatus("");
        }
    }

    function applyStatus(raw) {
        const data = root.parse(raw);
        if (!data) {
            root.syncing = false;
            root.report("Google Calendar helper failed");
            return;
        }

        if (data.ok === false) {
            root.syncing = false;
            root.needsReauth = data.reauth === true;
            root.report(data.error || "Google Calendar is unavailable");
            return;
        }

        root.configured = data.configured === true;
        root.hasSecret = data.hasSecret === true;
        root.connected = data.connected === true;
        root.account = typeof data.account === "string" ? data.account : "";
        root.clientId = typeof data.clientId === "string" ? data.clientId : "";
        root.calendarCount = Array.isArray(data.calendars)
            ? data.calendars.length : 0;
        root.lastSync = Number(data.lastSync) || 0;

        // The status document doubles as the offline snapshot, so a shell
        // restart paints the last sync before the network answers.
        if (Array.isArray(data.events)) {
            root.remoteEvents = data.events;
            root.publish();
        }

        if (data.error)
            root.report(String(data.error));
        else
            root.clearError();

        if (root.connected) {
            root.needsReauth = false;
            root.startSync();
        }
    }

    // ── sync ───────────────────────────────────────────────────────────────
    function startSync() {
        if (!root.connected || root.needsReauth)
            return;
        if (root.syncProcess.running)
            return;

        root.lastAttempt = Date.now() / 1000;
        root.syncing = true;
        root.syncProcess.running = true;
    }

    property Process syncProcess: Process {
        id: syncProc
        command: ["python3", root.helper, "--state", root.statePath, "sync"]

        property bool handled: false

        onStarted: syncProc.handled = false

        stdout: StdioCollector {
            onStreamFinished: {
                syncProc.handled = true;
                root.applySync(text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.syncing = false;
            if (!syncProc.handled)
                root.applySync("");
        }
    }

    function applySync(raw) {
        const data = root.parse(raw);
        if (!data || data.ok !== true) {
            root.needsReauth = !!data && data.reauth === true;
            root.report((data && data.error) || "Google Calendar sync failed");
            return;
        }

        root.connected = true;
        root.needsReauth = false;
        if (typeof data.account === "string" && data.account !== "")
            root.account = data.account;
        if (Array.isArray(data.calendars))
            root.calendarCount = data.calendars.length;
        root.lastSync = Number(data.lastSync) || Date.now() / 1000;
        if (Array.isArray(data.events))
            root.remoteEvents = data.events;

        root.clearError();
        root.publish();
    }

    // ── add ────────────────────────────────────────────────────────────────
    property var addQueue: []
    property var addCurrent: null

    function pumpAdd() {
        if (root.addCurrent !== null || root.addProcess.running)
            return;
        if (root.addQueue.length === 0)
            return;

        const next = root.addQueue[0];
        root.addQueue = root.addQueue.slice(1);
        root.addCurrent = next;
        root.addProcess.command = [
            "python3", root.helper, "--state", root.statePath,
            "add", "--json", JSON.stringify(next.event),
        ];
        root.addProcess.running = true;
    }

    property Process addProcess: Process {
        id: addProc
        command: []

        property bool handled: false

        onStarted: addProc.handled = false

        stdout: StdioCollector {
            onStreamFinished: {
                addProc.handled = true;
                root.applyAdd(text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!addProc.handled)
                root.applyAdd("");
            root.addCurrent = null;
            root.pumpAdd();
        }
    }

    function applyAdd(raw) {
        const current = root.addCurrent;
        const data = root.parse(raw);
        if (!current)
            return;

        if (!data || data.ok !== true || !data.event) {
            // Roll the optimistic row back; the form is already closed, so the
            // sheet's error line is the only place the user learns about it.
            root.remoteEvents = root.remoteEvents.filter(
                event => event.uid !== current.pendingUid);
            root.needsReauth = !!data && data.reauth === true;
            root.report((data && data.error)
                || "Could not add the event to Google Calendar");
            root.publish();
            return;
        }

        const created = data.event;
        let replaced = false;
        const next = [];
        for (const item of root.remoteEvents) {
            if (item.uid === current.pendingUid) {
                next.push(created);
                replaced = true;
            } else {
                next.push(item);
            }
        }
        if (!replaced)
            next.push(created);

        root.remoteEvents = next;
        root.clearError();
        root.publish();
    }

    // ── disconnect ─────────────────────────────────────────────────────────
    function disconnect() {
        if (root.disconnectProcess.running)
            return;
        root.disconnectProcess.running = true;
    }

    property Process disconnectProcess: Process {
        id: disconnectProc
        command: ["python3", root.helper, "--state", root.statePath, "disconnect"]

        property bool handled: false

        onStarted: disconnectProc.handled = false

        stdout: StdioCollector {
            onStreamFinished: {
                disconnectProc.handled = true;
                root.applyDisconnect(text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!disconnectProc.handled)
                root.applyDisconnect("");
        }
    }

    function applyDisconnect(raw) {
        const data = root.parse(raw);
        if (!data || data.ok !== true) {
            root.report((data && data.error) || "Could not disconnect Google Calendar");
            return;
        }

        root.connected = false;
        root.needsReauth = false;
        root.syncing = false;
        root.account = "";
        root.calendarCount = 0;
        root.lastSync = 0;
        root.remoteEvents = [];
        root.clearError();
        root.publish();
    }
}
