pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "."

// Notification center state: the notification daemon itself, the persisted
// history of the last `maxHistory` notifications, the do-not-disturb mode and
// the unread counter behind the bar bell.
//
// The daemon lives here so exactly one NotificationServer exists no matter
// which UI surface is created first (bar, overlay cards or history panel). The
// history is a JSON document under ~/.cache/quickshell that survives shell
// restarts; the active cards remain Quickshell's tracked notifications.
//
// Do not disturb never stops the daemon and never drops a notification from
// the history. It suppresses the live card surface and the shell-side chime;
// cards that were already on screen when DND is turned on are expired
// immediately so they cannot replay after DND is turned back off.
QtObject {
    id: root

    // History cap. The list stays newest-first, both in memory and on disk.
    readonly property int maxHistory: 50

    property bool dnd: false
    // Set by the center panel. While it is open, arrivals are not counted as
    // unread because they are visible in the list.
    property bool panelOpen: false
    property int unread: 0

    property bool stateLoaded: false
    property bool stateDirReady: false

    readonly property ListModel history: ListModel {}

    // The single notification server. Notification.qml renders its tracked
    // notifications; this service records every arrival in `history`.
    property NotificationServer server: NotificationServer {
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        keepOnReload: true

        onNotification: n => root.handleNotification(n)
    }

    // Quickshell's notification daemon has no audio output, so the shell
    // chimes itself through the shared EventSoundService. Do-not-disturb
    // silences it; the service owns player selection and burst coalescing.
    readonly property var sound: EventSoundService

    function handleNotification(n) {
        // Live cards are suppressed by do-not-disturb and while the center is
        // open (it is drawn on the same right edge, so a popup would overlap).
        const showCard = !root.dnd && !root.panelOpen;

        // keepOnReload re-emits the notifications that were live during a QML
        // reload. They are already in the history, so only their card state
        // needs restoring.
        if (n.lastGeneration) {
            n.tracked = showCard;
            return;
        }

        // The desktop specification asks transient notifications to skip
        // every persistence surface, so they never enter the history. They
        // still show a live card unless DND is on or the center is open.
        if (n.transient) {
            n.tracked = showCard;
            return;
        }

        const now = Date.now();
        root.history.insert(0, {
            key: now + "-" + n.id,
            time: now,
            appName: n.appName,
            appIcon: n.appIcon,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
        });

        if (root.history.count > root.maxHistory)
            root.history.remove(root.history.count - 1);

        if (!root.panelOpen)
            root.unread++;

        root.save();
        // The chime helper reports its own failures as notifications; skip
        // the sound for those so a broken audio path cannot recurse.
        if (n.appName !== "kolir-sound")
            root.sound.playNotification(n.hints["sound-file"]);

        // The card surface stays available for normal notifications; under
        // DND or with the center open it is recorded above and discarded.
        n.tracked = showCard;
    }

    function setPanelOpen(value) {
        root.panelOpen = !!value;
        if (root.panelOpen)
            root.unread = 0;
    }

    function remove(key) {
        const wanted = String(key);
        for (let i = 0; i < root.history.count; i++) {
            if (String(root.history.get(i).key) === wanted) {
                root.history.remove(i);
                break;
            }
        }

        root.save();
    }

    function clear() {
        root.history.clear();
        root.unread = 0;
        root.save();
    }

    function setDnd(value) {
        const next = !!value;
        if (root.dnd === next)
            return;

        root.dnd = next;
        root.sound.muted = next;
        root.save();

        if (root.dnd)
            root.suppressTracked();
    }

    function toggleDnd() {
        root.setDnd(!root.dnd);
    }

    // Close cards that were on screen when DND was enabled. They are already
    // in the history, so nothing is lost, and they will not pop up later.
    function suppressTracked() {
        const values = root.server.trackedNotifications.values;
        const pending = [];
        for (let i = 0; i < values.length; i++)
            pending.push(values[i]);

        for (let i = 0; i < pending.length; i++)
            pending[i].expire();
    }

    function save() {
        if (!root.stateLoaded)
            return;

        root.saveTimer.restart();
    }

    function writeState() {
        if (!root.stateDirReady)
            return;

        const items = [];
        for (let i = 0; i < root.history.count; i++) {
            const item = root.history.get(i);
            items.push({
                key: item.key,
                time: item.time,
                appName: item.appName,
                appIcon: item.appIcon,
                summary: item.summary,
                body: item.body,
                urgency: item.urgency,
            });
        }

        root.stateFile.setText(JSON.stringify({
            version: 1,
            dnd: root.dnd,
            notifications: items,
        }));
    }

    function loadState() {
        const content = root.stateFile.text();
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);
                const items = Array.isArray(parsed.notifications)
                    ? parsed.notifications : [];

                for (let i = 0; i < items.length && i < root.maxHistory; i++) {
                    const item = items[i];
                    if (!item || typeof item !== "object")
                        continue;

                    root.history.append({
                        key: String(item.key ?? (Date.now() + "-" + i)),
                        time: Number(item.time) || 0,
                        appName: typeof item.appName === "string" ? item.appName : "",
                        appIcon: typeof item.appIcon === "string" ? item.appIcon : "",
                        summary: typeof item.summary === "string" ? item.summary : "",
                        body: typeof item.body === "string" ? item.body : "",
                        urgency: Number(item.urgency) || 0,
                    });
                }

                if (typeof parsed.dnd === "boolean")
                    root.dnd = parsed.dnd;
            } catch (error) {
                console.warn("NotificationService: invalid state file:", error);
            }
        }

        root.sound.muted = root.dnd;
        root.stateLoaded = true;
    }

    property Timer saveTimer: Timer {
        interval: 300
        repeat: false

        onTriggered: root.writeState()
    }

    // The Quickshell cache directory is normally created by `kolir setup`
    // (colors.json lives there). Create it defensively anyway, then seed the
    // state file before FileView starts watching it, so the first load does
    // not log a "file does not exist" warning.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "notifications", ShellPaths.quickshellCache, ShellPaths.notificationState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("NotificationService: cannot create",
                    ShellPaths.quickshellCache);
                root.stateLoaded = true;
                return;
            }

            root.stateDirReady = true;
        }
    }

    property FileView stateFile: FileView {
        path: root.stateDirReady ? ShellPaths.notificationState : ""
        atomicWrites: true

        onLoaded: root.loadState()
        onLoadFailed: root.stateLoaded = true
    }
}
