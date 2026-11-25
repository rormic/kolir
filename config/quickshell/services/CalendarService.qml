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
// Storage is deliberately behind a backend object (default: the local JSON
// file CalendarLocalBackend writes to ~/.cache/quickshell/calendar.json).
// Assigning a CalDAV/Google backend that implements the same contract —
// `load()`, `create()`, `update()`, `remove()` and the
// `loaded`/`changed`/`failed` signals — switches storage without touching the
// UI or this API.
//
// Events keep the Google Calendar / iCalendar shape described in
// calendar/CalendarModel.js: uid, summary, description, location, start, end,
// allDay, timeZone and calendarId, plus any remote metadata the backend adds.
// `timeZone` is the machine's IANA zone, resolved once at startup, so a sync
// backend can turn the wall-clock start into an absolute instant.
QtObject {
    id: root

    // Swappable persistence. See calendar/CalendarLocalBackend.qml for the
    // contract a CalDAV/Google backend has to implement.
    property var backend: CalendarLocalBackend {}

    property var events: []
    property bool ready: false
    property string lastError: ""
    property string timeZone: "UTC"

    readonly property string provider: root.backend && root.backend.provider
        ? root.backend.provider : "unknown"

    // { "yyyymmdd": count } for the grid's presence dots. Rebuilt only when
    // `events` changes, so 42 cells do not rescan the list on every repaint.
    readonly property var dayCounts: Model.dayCounts(root.events)

    // ── Backend plumbing ───────────────────────────────────────────────────
    function load() {
        if (root.backend && typeof root.backend.load === "function")
            root.backend.load();
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
