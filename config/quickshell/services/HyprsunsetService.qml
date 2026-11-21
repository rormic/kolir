pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "hyprsunset/Solar.js" as Solar

// Hyprsunset state, manual controls and the bar-owned automatic schedule.
//
// hyprsunset exposes its live state through the IPC socket:
//   hyprctl hyprsunset identity get   -> true (off) / false (on)
//   hyprctl hyprsunset temperature    -> current Kelvin
// The schedule lives here instead of in hyprsunset.conf so both planners
// cannot fight over the CTM.
QtObject {
    id: root

    readonly property int minTemperature: 2000
    readonly property int maxTemperature: 6500

    // State exposed to the popup. It follows the user's intent; the raw
    // values reported by hyprsunset live in actual* below.
    property bool available: false
    property bool enabled: false
    property int temperature: 4000

    // Last state reported by hyprsunset.
    property bool actualEnabled: false
    property int actualTemperature: 4000

    // Persisted user choices.
    property bool savedEnabled: false
    property int savedTemperature: 4000
    property bool autoSchedule: false
    property string scheduleMode: "sun"
    property int onHour: 21
    property int onMinute: 0
    property int offHour: 7
    property int offMinute: 0

    // Location used for the sunrise/sunset schedule. Coordinates are
    // detected from the public IP and cached in the bar state file.
    property bool locationAvailable: false
    property real latitude: 0
    property real longitude: 0
    property string locationCity: ""
    property string locationCountry: ""
    property real locationUpdated: 0
    property bool locationRefreshing: false
    property string locationError: ""
    property bool locationFetchOk: false

    property date now: new Date()

    property bool stateLoaded: false
    property bool identityLoaded: false
    property bool temperatureLoaded: false
    property bool startupApplied: false
    property bool manualOverride: false
    property int pendingQueries: 0

    // -1 = unknown, 0 = off, 1 = on. Used so a manual override survives
    // until the next scheduled boundary instead of being corrected on the
    // next 30-second tick.
    property int lastScheduledState: -1

    readonly property bool sunMode: root.scheduleMode === "sun"
    readonly property int onMinutes: root.onHour * 60 + root.onMinute
    readonly property int offMinutes: root.offHour * 60 + root.offMinute
    readonly property bool fixedScheduleValid: root.onMinutes !== root.offMinutes

    readonly property var sunTimes: root.computeSunTimes(root.now, root.latitude, root.longitude)
    readonly property bool sunTimesAvailable: root.locationAvailable
        && root.sunTimes.sunrise !== null
        && root.sunTimes.sunset !== null

    readonly property bool scheduleValid: root.sunMode
        ? root.sunTimesAvailable
        : root.fixedScheduleValid
    readonly property bool scheduleActive: root.autoSchedule && root.scheduleValid

    readonly property string sunriseLabel: root.sunTimes.sunrise
        ? root.formatDate(root.sunTimes.sunrise)
        : "—"
    readonly property string sunsetLabel: root.sunTimes.sunset
        ? root.formatDate(root.sunTimes.sunset)
        : "—"

    readonly property string locationLabel: {
        if (root.locationRefreshing)
            return "Detecting location…";

        if (root.locationAvailable) {
            let label = root.locationCity || "Detected location";
            if (root.locationCountry)
                label += ", " + root.locationCountry;
            return label + " · auto";
        }

        if (root.locationError)
            return root.locationError;

        return "Location not set";
    }

    readonly property string scheduleLabel: {
        if (!root.scheduleActive)
            return "";

        const event = root.nextScheduleEvent();
        if (!event)
            return "";

        const time = root.formatDate(event.date);
        if (root.manualOverride)
            return "Manual · until " + time;

        if (root.sunMode)
            return (event.on ? "Auto · sunset at " : "Auto · sunrise at ") + time;

        return root.expectedScheduleOn() ? ("Auto · on until " + time)
                                         : ("Auto · off until " + time);
    }

    readonly property string scheduleStatusText: {
        if (!root.autoSchedule)
            return "Off · use the switch to enable";

        if (!root.scheduleValid) {
            if (root.sunMode) {
                if (root.locationRefreshing)
                    return "Detecting location…";
                return "Sunrise/sunset unavailable";
            }
            return "Set different on/off times";
        }

        const label = root.scheduleLabel;
        return label !== "" ? label : "Sunrise/sunset unavailable";
    }

    function clampTemperature(value) {
        return Math.max(root.minTemperature,
            Math.min(root.maxTemperature, Math.round(value)));
    }

    function pad2(value) {
        return (value < 10 ? "0" : "") + value;
    }

    function formatTime(hour, minute) {
        return root.pad2(hour) + ":" + root.pad2(minute);
    }

    function formatDate(date) {
        return root.formatTime(date.getHours(), date.getMinutes());
    }

    function currentMinutes() {
        return root.now.getHours() * 60 + root.now.getMinutes();
    }

    // True between the on time and the off time. A schedule crossing
    // midnight (for example 21:00 -> 07:00) is handled by the second branch.
    function expectedFixedOn() {
        if (!root.fixedScheduleValid)
            return false;

        const minutes = root.currentMinutes();
        if (root.onMinutes < root.offMinutes)
            return minutes >= root.onMinutes && minutes < root.offMinutes;

        return minutes >= root.onMinutes || minutes < root.offMinutes;
    }

    function expectedSunOn() {
        const times = root.sunTimes;
        if (!times.sunrise || !times.sunset)
            return false;

        const now = root.now.getTime();
        return now < times.sunrise.getTime() || now >= times.sunset.getTime();
    }

    function expectedScheduleOn() {
        return root.sunMode ? root.expectedSunOn() : root.expectedFixedOn();
    }

    function nextFixedEvent() {
        const events = [];

        for (const item of [
            { hour: root.onHour, minute: root.onMinute, on: true },
            { hour: root.offHour, minute: root.offMinute, on: false },
        ]) {
            const date = new Date(root.now);
            date.setHours(item.hour, item.minute, 0, 0);
            if (date.getTime() <= root.now.getTime())
                date.setDate(date.getDate() + 1);
            events.push({ date: date, on: item.on });
        }

        events.sort((a, b) => a.date.getTime() - b.date.getTime());
        return events[0];
    }

    function nextSunEvent() {
        const times = root.sunTimes;
        if (!times.sunrise || !times.sunset)
            return null;

        const now = root.now.getTime();
        if (now < times.sunrise.getTime())
            return { date: times.sunrise, on: false };
        if (now < times.sunset.getTime())
            return { date: times.sunset, on: true };

        const tomorrow = new Date(root.now);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const nextTimes = root.computeSunTimes(tomorrow, root.latitude, root.longitude);
        if (!nextTimes.sunrise)
            return null;

        return { date: nextTimes.sunrise, on: false };
    }

    function nextScheduleEvent() {
        if (!root.scheduleActive)
            return null;

        return root.sunMode ? root.nextSunEvent() : root.nextFixedEvent();
    }

    // NOAA sunrise equation. The result is a local Date for the requested
    // local calendar day, so it also works across DST and western longitudes.
    // The equations live in hyprsunset/Solar.js; these wrappers keep the
    // service API and feed it the only piece of state it needs.
    function computeSunTimes(date, latitude, longitude) {
        return Solar.computeSunTimes(date, latitude, longitude, root.locationAvailable);
    }

    function calculateSunEvent(date, latitude, longitude, rising) {
        return Solar.calculateSunEvent(date, latitude, longitude, rising);
    }

    // A toggle coming from the popup or IPC is a manual override while the
    // automatic schedule is active. The next boundary takes control again.
    function setEnabledManual(value) {
        root.now = new Date();
        if (root.scheduleActive && root.startupApplied)
            root.manualOverride = !!value !== root.expectedScheduleOn();

        root.setEnabled(value);
    }

    function setEnabled(value) {
        const next = !!value;

        root.enabled = next;
        root.savedEnabled = next;
        root.tempWriteTimer.stop();

        if (next)
            root.enqueue(["temperature", String(root.temperature)]);
        else
            root.enqueue(["identity", "true"]);

        root.saveState();
    }

    function setTemperature(value) {
        const next = root.clampTemperature(Number(value));
        if (isNaN(next))
            return;

        const wasEnabled = root.enabled;
        root.temperature = next;
        root.savedTemperature = next;

        // Touching the temperature implies that the filter should be on.
        if (!wasEnabled) {
            root.enabled = true;
            root.savedEnabled = true;
            root.now = new Date();

            if (root.scheduleActive && root.startupApplied)
                root.manualOverride = !root.expectedScheduleOn();
        }

        // Throttle rather than debounce so the screen follows a continuous
        // drag instead of waiting for the pointer to stop.
        if (!root.tempWriteTimer.running)
            root.tempWriteTimer.start();

        root.saveState();
    }

    function setScheduleEnabled(value) {
        const next = !!value && root.scheduleValid;
        if (next === root.autoSchedule)
            return;

        root.autoSchedule = next;
        root.manualOverride = false;
        root.lastScheduledState = -1;

        if (next) {
            if (root.sunMode && !root.locationAvailable)
                root.refreshLocation(true);
            root.applySchedule(true);
        } else {
            root.savedEnabled = root.enabled;
        }

        root.saveState();
    }

    function setScheduleMode(mode) {
        const next = mode === "fixed" ? "fixed" : "sun";
        if (next === root.scheduleMode)
            return;

        root.scheduleMode = next;
        root.manualOverride = false;
        root.lastScheduledState = -1;

        if (next === "sun" && (!root.locationAvailable || root.locationIsStale()))
            root.refreshLocation(true);

        if (root.autoSchedule && root.scheduleValid)
            root.applySchedule(true);

        root.saveState();
    }

    function setOnTime(hour, minute) {
        const h = Number(hour);
        const m = Number(minute);
        if (isNaN(h) || isNaN(m))
            return;

        root.onHour = ((Math.round(h) % 24) + 24) % 24;
        root.onMinute = ((Math.round(m) % 60) + 60) % 60;
        root.afterScheduleEdited();
    }

    function setOffTime(hour, minute) {
        const h = Number(hour);
        const m = Number(minute);
        if (isNaN(h) || isNaN(m))
            return;

        root.offHour = ((Math.round(h) % 24) + 24) % 24;
        root.offMinute = ((Math.round(m) % 60) + 60) % 60;
        root.afterScheduleEdited();
    }

    function afterScheduleEdited() {
        root.lastScheduledState = -1;
        root.manualOverride = false;

        if (!root.fixedScheduleValid && !root.sunMode) {
            root.autoSchedule = false;
            root.savedEnabled = root.enabled;
        } else if (root.autoSchedule && root.scheduleValid) {
            root.applySchedule(true);
        }

        root.saveState();
    }

    function applySchedule(force) {
        if (!root.startupApplied || !root.scheduleActive)
            return;

        root.now = new Date();
        const expected = root.expectedScheduleOn();
        if (!force && root.lastScheduledState === (expected ? 1 : 0))
            return;

        root.lastScheduledState = expected ? 1 : 0;
        root.manualOverride = false;
        root.temperature = root.savedTemperature;
        root.enabled = expected;
        root.savedEnabled = expected;

        if (expected)
            root.enqueue(["temperature", String(root.savedTemperature)]);
        else
            root.enqueue(["identity", "true"]);

        root.saveState();
    }

    function applySavedManualState() {
        root.temperature = root.savedTemperature;
        root.enabled = root.savedEnabled;

        if (root.savedEnabled) {
            if (!root.actualEnabled || root.actualTemperature !== root.savedTemperature)
                root.enqueue(["temperature", String(root.savedTemperature)]);
        } else if (root.actualEnabled) {
            root.enqueue(["identity", "true"]);
        }
    }

    // Reconcile the live service with the desired state. This catches
    // hyprsunset restarts, external hyprctl changes and drift after resume.
    // A manual override while the schedule is active is enforced as the
    // desired state until the next scheduled boundary.
    function reconcile() {
        if (!root.startupApplied || !root.available)
            return;
        if (root.commandRunning || root.commandQueue.length > 0 || root.tempWriteTimer.running)
            return;

        root.now = new Date();
        const desiredEnabled = root.scheduleActive && !root.manualOverride
            ? root.expectedScheduleOn()
            : root.savedEnabled;
        const desiredTemperature = root.savedTemperature;

        root.enabled = desiredEnabled;
        root.temperature = desiredTemperature;
        root.savedEnabled = desiredEnabled;

        if (desiredEnabled) {
            if (!root.actualEnabled || root.actualTemperature !== desiredTemperature)
                root.enqueue(["temperature", String(desiredTemperature)]);
        } else if (root.actualEnabled) {
            root.enqueue(["identity", "true"]);
        }
    }

    function maybeApplyStartupState() {
        if (root.startupApplied || !root.stateLoaded || !root.identityLoaded
                || !root.temperatureLoaded || !root.available)
            return;

        root.startupApplied = true;
        root.manualOverride = false;

        if (root.autoSchedule && root.scheduleActive)
            root.applySchedule(true);
        else
            root.applySavedManualState();
    }

    function locationIsStale() {
        return root.locationUpdated <= 0
            || Date.now() - root.locationUpdated > 7 * 86400000;
    }

    function refreshLocation(force) {
        if (root.locationProc.running)
            return;
        if (!force && root.locationAvailable && !root.locationIsStale())
            return;

        root.locationRefreshing = true;
        root.locationError = "";
        root.locationFetchOk = false;
        root.locationProc.running = true;
    }

    function handleLocationResponse(text) {
        try {
            const data = JSON.parse(text);
            if (!data || data.success === false)
                throw new Error(data && data.message ? data.message : "lookup failed");

            const latitude = Number(data.latitude);
            const longitude = Number(data.longitude);
            if (!isFinite(latitude) || !isFinite(longitude)
                    || latitude < -90 || latitude > 90
                    || longitude < -180 || longitude > 180)
                throw new Error("invalid coordinates");

            root.latitude = latitude;
            root.longitude = longitude;
            root.locationCity = typeof data.city === "string" ? data.city : "";
            root.locationCountry = typeof data.country === "string" ? data.country : "";
            root.locationUpdated = Date.now();
            root.locationAvailable = true;
            root.locationFetchOk = true;
            root.locationError = "";
            root.lastScheduledState = -1;

            root.saveState();

            if (root.autoSchedule && root.scheduleValid)
                root.applySchedule(true);
        } catch (error) {
            root.locationError = "Location lookup failed";
            console.warn("HyprsunsetService: location lookup failed:", error);
        }
    }

    function refresh() {
        if (root.identityProc.running || root.temperatureProc.running)
            return;

        root.pendingQueries = 2;
        root.identityProc.running = true;
        root.temperatureProc.running = true;
    }

    function queryFinished() {
        if (root.pendingQueries > 0)
            root.pendingQueries--;

        if (root.pendingQueries === 0) {
            root.maybeApplyStartupState();
            root.reconcile();
        }
    }

    function enqueue(args) {
        root.commandQueue.push(args);
        root.runNextCommand();
    }

    function runNextCommand() {
        if (root.commandRunning || root.commandQueue.length === 0)
            return;

        root.commandRunning = true;
        const args = root.commandQueue.shift();
        commandProc.command = ["hyprctl", "hyprsunset"].concat(args);
        commandProc.running = true;
    }

    function loadState() {
        const content = root.stateFile.text();
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);

                root.scheduleMode = parsed.mode === "fixed" ? "fixed" : "sun";

                const on = root.parseTime(parsed.on);
                if (on) {
                    root.onHour = on.hour;
                    root.onMinute = on.minute;
                }

                const off = root.parseTime(parsed.off);
                if (off) {
                    root.offHour = off.hour;
                    root.offMinute = off.minute;
                }

                const temperature = Number(parsed.temperature);
                if (!isNaN(temperature))
                    root.savedTemperature = root.clampTemperature(temperature);

                const hasLatitude = parsed.latitude !== null && parsed.latitude !== undefined;
                const hasLongitude = parsed.longitude !== null && parsed.longitude !== undefined;
                const latitude = Number(parsed.latitude);
                const longitude = Number(parsed.longitude);

                if (hasLatitude && hasLongitude
                        && isFinite(latitude) && isFinite(longitude)
                        && latitude >= -90 && latitude <= 90
                        && longitude >= -180 && longitude <= 180) {
                    root.latitude = latitude;
                    root.longitude = longitude;
                    root.locationAvailable = true;
                    root.locationCity = typeof parsed.city === "string" ? parsed.city : "";
                    root.locationCountry = typeof parsed.country === "string" ? parsed.country : "";
                    root.locationUpdated = Number(parsed.locationUpdated) || 0;
                }

                root.savedEnabled = !!parsed.enabled;
                root.autoSchedule = !!parsed.auto;

                root.enabled = root.savedEnabled;
                root.temperature = root.savedTemperature;
            } catch (error) {
                console.warn("HyprsunsetService: invalid state file:", error);
            }
        }

        root.stateLoaded = true;

        if (root.sunMode && (!root.locationAvailable || root.locationIsStale()))
            root.refreshLocation(true);

        root.maybeApplyStartupState();
    }

    function parseTime(value) {
        const match = String(value ?? "").match(/^([01]?\d|2[0-3]):([0-5]\d)$/);
        if (!match)
            return null;

        return {
            hour: Number(match[1]),
            minute: Number(match[2]),
        };
    }

    function saveState() {
        if (!root.stateLoaded)
            return;

        root.saveTimer.restart();
    }

    function writeState() {
        root.stateFile.setText(JSON.stringify({
            enabled: root.savedEnabled,
            temperature: root.savedTemperature,
            auto: root.autoSchedule,
            mode: root.scheduleMode,
            on: root.formatTime(root.onHour, root.onMinute),
            off: root.formatTime(root.offHour, root.offMinute),
            latitude: root.locationAvailable ? root.latitude : null,
            longitude: root.locationAvailable ? root.longitude : null,
            city: root.locationCity,
            country: root.locationCountry,
            locationUpdated: root.locationUpdated,
        }, null, 2));
    }

    property var commandQueue: []
    property bool commandRunning: false

    property FileView stateFile: FileView {
        path: ShellPaths.hyprsunsetState
        atomicWrites: true

        onLoaded: root.loadState()
        onLoadFailed: {
            root.stateLoaded = true;
            root.writeState();
            root.refreshLocation(true);
            root.maybeApplyStartupState();
        }
    }

    property Process identityProc: Process {
        command: ["hyprctl", "hyprsunset", "identity", "get"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value === "true" || value === "false") {
                    root.actualEnabled = value === "false";
                    root.identityLoaded = true;
                    root.available = root.identityLoaded && root.temperatureLoaded;
                } else {
                    root.identityLoaded = false;
                    root.available = false;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.identityLoaded = false;
                root.available = false;
            }
            root.queryFinished();
        }
    }

    property Process temperatureProc: Process {
        command: ["hyprctl", "hyprsunset", "temperature"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const value = Number(text.trim());
                if (!isNaN(value) && value >= 1000 && value <= 20000) {
                    root.actualTemperature = root.clampTemperature(value);
                    root.temperatureLoaded = true;
                    root.available = root.identityLoaded && root.temperatureLoaded;
                } else {
                    root.temperatureLoaded = false;
                    root.available = false;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.temperatureLoaded = false;
                root.available = false;
            }
            root.queryFinished();
        }
    }

    property Process locationProc: Process {
        command: ["curl", "-fsSL", "--max-time", "8", "https://ipwho.is/"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.handleLocationResponse(text)
        }

        onExited: (exitCode, exitStatus) => {
            root.locationRefreshing = false;

            if (exitCode !== 0 || !root.locationFetchOk) {
                if (root.locationError === "")
                    root.locationError = "Location lookup failed";
                console.warn("HyprsunsetService: location request exited with", exitCode);
            }
        }
    }

    property Process commandProc: Process {
        running: false

        onExited: (exitCode, exitStatus) => {
            root.commandRunning = false;

            if (exitCode !== 0) {
                console.warn("HyprsunsetService: hyprctl command failed with code", exitCode);
                root.available = false;
                root.refresh();
            }

            root.runNextCommand();
        }
    }

    property Timer tempWriteTimer: Timer {
        interval: 80
        repeat: false

        onTriggered: root.enqueue(["temperature", String(root.temperature)])
    }

    property Timer saveTimer: Timer {
        interval: 300
        repeat: false

        onTriggered: root.writeState()
    }

    property Timer scheduleTimer: Timer {
        interval: 30000
        repeat: true
        running: true

        onTriggered: {
            root.now = new Date();

            if (!root.startupApplied)
                return;

            root.applySchedule(false);
            root.refresh();
        }
    }

    // hyprsunset is started by graphical-session.target. Retry until it is
    // ready so a login race does not leave the bar without state.
    property Timer retryTimer: Timer {
        interval: 5000
        repeat: true
        running: !root.available

        onTriggered: root.refresh()
    }

    property IpcHandler ipc: IpcHandler {
        target: "hyprsunset"

        function toggle(): void {
            root.setEnabledManual(!root.enabled);
        }

        function enable(): void {
            root.setEnabledManual(true);
        }

        function disable(): void {
            root.setEnabledManual(false);
        }

        function setTemperature(kelvin: string): void {
            root.setTemperature(Number(kelvin));
        }

        function setAuto(value: string): void {
            root.setScheduleEnabled(value === "true" || value === "1");
        }

        function setMode(mode: string): void {
            root.setScheduleMode(mode);
        }

        function setOnTime(hour: string, minute: string): void {
            root.setOnTime(Number(hour), Number(minute));
        }

        function setOffTime(hour: string, minute: string): void {
            root.setOffTime(Number(hour), Number(minute));
        }

        function refreshLocation(): void {
            root.refreshLocation(true);
        }

        function refresh(): void {
            root.refresh();
        }
    }

    Component.onCompleted: {
        root.refresh();
    }
}
