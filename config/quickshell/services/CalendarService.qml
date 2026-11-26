pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "calendar"
import "calendar/CalendarModel.js" as Model

// Calendar events: the persisted model behind CalendarPopup's day list and
// presence dots.
//
// Storage is deliberately behind a backend object. The default is
// calendar/CalendarGoogleBackend.qml, a hybrid backend: the local JSON file
// (calendar/CalendarLocalBackend.qml → ~/.cache/quickshell/calendar.json keeps
// the events created without an account, while the Google helper adds the
// connected account's calendars to the same snapshot. When no account is
// connected the backend behaves exactly like the local one. Assigning another
// backend that implements the same contract — `load()`, `create()`, `update()`,
// `remove()` and the `loaded`/`changed`/`failed` signals — switches storage
// without touching the UI or this API.
//
// Events keep the Google Calendar / iCalendar shape described in
// calendar/CalendarModel.js: uid, summary, description, location, start, end,
// allDay, timeZone and calendarId, plus any remote metadata the backend adds.
// `timeZone` is the machine's IANA zone, resolved once at startup, so a sync
// backend can turn the wall-clock start into an absolute instant.
//
// Google events arrive with `readOnly: true`; updateEvent/removeEvent refuse
// them here as well as in the backend, because the sync is read-plus-add.
QtObject {
    id: root

    // Swappable persistence. See calendar/CalendarGoogleBackend.qml.
    property var backend: CalendarGoogleBackend {}

    property var events: []
    property bool ready: false
    property string lastError: ""
    property string timeZone: "UTC"

    readonly property string provider: root.backend && root.backend.provider
        ? root.backend.provider : "unknown"

    // Google sync state, forwarded for the settings page and the calendar
    // sheet. A backend without these properties reports the "local" defaults
    // (the local file backend has no account and never syncs).
    readonly property bool googleConfigured: root.backend
        && root.backend.configured === true
    readonly property bool googleHasSecret: root.backend
        && root.backend.hasSecret === true
    readonly property bool googleConnected: root.backend
        && root.backend.connected === true
    readonly property bool googleSyncing: root.backend
        && root.backend.syncing === true
    readonly property bool googleNeedsReauth: root.backend
        && root.backend.needsReauth === true
    readonly property string googleAccount: root.backend
        && typeof root.backend.account === "string"
        ? root.backend.account : ""
    readonly property string googleClientId: root.backend
        && typeof root.backend.clientId === "string"
        ? root.backend.clientId : ""
    readonly property real googleLastSync: root.backend
        && Number(root.backend.lastSync) ? Number(root.backend.lastSync) : 0
    readonly property int googleCalendarCount: root.backend
        && Number(root.backend.calendarCount)
        ? Number(root.backend.calendarCount) : 0

    // { "yyyymmdd": count } for the grid's presence dots. Rebuilt only when
    // `events` changes, so 42 cells do not rescan the list on every repaint.
    readonly property var dayCounts: Model.dayCounts(root.events)

    // ── Backend plumbing ───────────────────────────────────────────────────
    function load() {
        if (root.backend && typeof root.backend.load === "function")
            root.backend.load();
    }

    // Re-read the cached snapshot and, when a Google account is connected,
    // refetch the account's calendars. CalendarPopup calls this on open (the
    // backend throttles that to one network attempt a minute); the settings
    // page and the `calendar sync` IPC pass `force` for an explicit refresh.
    function refresh(force) {
        if (root.backend && typeof root.backend.refresh === "function")
            root.backend.refresh(force === true);
    }

    function disconnectGoogle() {
        if (root.backend && typeof root.backend.disconnect === "function")
            root.backend.disconnect();
        else
            root.reportError("This calendar backend has no account to disconnect");
    }

    function applyEvents(list) {
        root.events = Model.normalizeList(list);
        root.ready = true;
        root.lastError = "";
    }

    function reportError(message) {
        root.lastError = String(message === undefined || message === null ? "" : message);
        if (root.lastError !== "")
            console.warn("CalendarService:", root.lastError);
    }

    // A property so replacing `backend` reconnects these handlers.
    property Connections backendSignals: Connections {
        target: root.backend

        function onLoaded(list) {
            root.applyEvents(list);
        }

        function onChanged(list) {
            root.applyEvents(list);
        }

        function onFailed(message) {
            root.reportError(message);
        }
    }

    // ── Queries ────────────────────────────────────────────────────────────
    function event(uid) {
        const wanted = String(uid);
        for (const item of root.events) {
            if (item.uid === wanted)
                return item;
        }
        return null;
    }

    function eventsOn(key) {
        return Model.eventsOn(root.events, key);
    }

    function eventsInMonth(year, monthIndex) {
        return Model.eventsInMonth(root.events, year, monthIndex);
    }

    function countOn(key) {
        return root.dayCounts[String(key)] || 0;
    }

    function hasEventsOn(key) {
        return root.countOn(key) > 0;
    }

    // ── Writes ─────────────────────────────────────────────────────────────
    // fields: { summary, dayKey, allDay, startMinutes, endMinutes,
    //           description?, location?, timeZone? }
    // Returns the new event immediately. With a connected Google account the
    // backend first returns it as an optimistic `pending` row; Google's insert
    // answer then replaces it, and the final uid is Google's iCalUID.
    function addEvent(fields) {
        if (!root.backend || typeof root.backend.create !== "function") {
            root.reportError("Calendar backend cannot create events");
            return null;
        }

        const event = Model.buildEvent(Object.assign(
            { timeZone: root.timeZone }, fields || {}));
        if (!event) {
            root.reportError("Could not create the event");
            return null;
        }

        root.backend.create(event);
        return event;
    }

    function updateEvent(uid, fields) {
        const existing = root.event(uid);
        if (!existing)
            return null;

        if (existing.readOnly === true) {
            root.reportError("Google Calendar events are read-only");
            return null;
        }

        if (!root.backend || typeof root.backend.update !== "function") {
            root.reportError("Calendar backend cannot update events");
            return null;
        }

        const event = Model.updateEvent(existing, Object.assign(
            { timeZone: existing.timeZone || root.timeZone }, fields || {}));
        if (!event) {
            root.reportError("Could not update the event");
            return null;
        }

        root.backend.update(event);
        return event;
    }

    function removeEvent(uid) {
        const existing = root.event(uid);
        if (existing && existing.readOnly === true) {
            root.reportError("Google Calendar events are read-only");
            return false;
        }

        if (!root.backend || typeof root.backend.remove !== "function") {
            root.reportError("Calendar backend cannot remove events");
            return false;
        }

        root.backend.remove(uid);
        return true;
    }

    // ── Machine time zone ──────────────────────────────────────────────────
    // QML's JS runtime has no IANA zone API, and Google needs a real zone name
    // (not an offset) to place a recurring event correctly. systemd knows the
    // configured zone; the /etc/localtime symlink is the fallback.
    property Process zoneProcess: Process {
        command: ["sh", "-c",
            "z=$(timedatectl show -p Timezone --value 2>/dev/null);"
            + " [ -n \"$z\" ] || z=$(readlink -f /etc/localtime 2>/dev/null"
            + " | sed -n 's|.*/zoneinfo/||p');"
            + " printf '%s' \"${z:-UTC}\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value !== "")
                    root.timeZone = value;
            }
        }
    }

    Component.onCompleted: root.load()
}
