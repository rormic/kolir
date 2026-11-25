import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "CalendarModel.js" as Model

// Local JSON persistence for CalendarService.
//
// This is the default backend, not a hard dependency: CalendarService talks
// only to the contract below, so a CalDAV/Google backend replaces this file
// without touching the calendar sheet or the event model.
//
// Backend contract
//   property string provider      // "local" now; a sync backend names itself
//   property bool ready
//   property var events           // canonical event objects (CalendarModel)
//   signal loaded(var events)     // first snapshot after load()
//   signal changed(var events)    // snapshot after create/update/remove
//   signal failed(string message)
//   function load()
//   function create(event)
//   function update(event)
//   function remove(uid)
//
// `events` is sorted by start; an implementation that talks to a server emits
// `changed` after the remote write succeeded, so a failed request leaves the
// previous snapshot in place.
QtObject {
    id: root

    readonly property string provider: "local"

    property bool ready: false
    property var events: []
    property bool stateDirReady: false
    property bool writeQueued: false

    signal loaded(var events)
    signal changed(var events)
    signal failed(string message)

    function load() {
        if (root.stateDirReady)
            root.stateFile.reload();
    }

    function create(event) {
        if (!event)
            return;

        const next = root.events.slice();
        next.push(event);
        root.commit(next);
    }

    function update(event) {
        if (!event)
            return;

        const next = [];
        let replaced = false;
        for (const existing of root.events) {
            if (existing.uid === event.uid) {
                next.push(event);
                replaced = true;
            } else {
                next.push(existing);
            }
        }

        if (!replaced)
            next.push(event);

        root.commit(next);
    }

    function remove(uid) {
        const wanted = String(uid);
        root.commit(root.events.filter(event => event.uid !== wanted));
    }

    function commit(next) {
        root.events = Model.sortEvents(next);
        root.saveState();
        root.changed(root.events);
    }

    function readState(content) {
        const parsed = Model.parseState(content);
        if (parsed === null) {
            console.warn("CalendarLocalBackend: invalid state file:",
                ShellPaths.calendarState);
            root.failed("Invalid calendar state file");
            root.events = [];
        } else {
            root.events = parsed;
        }

        if (root.ready) {
            root.changed(root.events);
            return;
        }

        root.ready = true;
        root.loaded(root.events);
    }

    function saveState() {
        if (!root.stateDirReady) {
            root.writeQueued = true;
            return;
        }

        root.writeQueued = false;
        root.stateFile.setText(Model.serializeState(root.events));
    }

    // Grow the cache directory and seed an empty state file once, so FileView
    // does not log a read failure on first run.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "calendar", ShellPaths.quickshellCache, ShellPaths.calendarState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("CalendarLocalBackend: cannot create",
                    ShellPaths.calendarState);
                root.failed("Cannot create the calendar state file");
                return;
            }

            root.stateDirReady = true;
            if (root.writeQueued)
                root.saveState();
        }
    }

    property FileView stateFile: FileView {
        path: ShellPaths.calendarState
        atomicWrites: true
        printErrors: false

        onLoaded: root.readState(this.text())
        // First run: the seeding Process above has not touched the file yet.
        onLoadFailed: root.readState("")
    }
}
