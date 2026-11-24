pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Battery state for the bar indicator.
//
// UPower's DisplayDevice aggregates every internal battery, so machines with
// two packs still get one percentage and one charge state. The indicator is
// hidden on desktops: `expected` is only true for a portable chassis or when
// UPower actually reports a battery. A laptop whose battery is missing from
// UPower (removed, dead, or the daemon not running) therefore keeps the chip
// and Battery.qml draws the alert glyph instead of a charge level.
QtObject {
    id: root

    // SMBIOS chassis types (DMI specification) that ship with an internal
    // battery: portable, laptop, notebook, hand held, sub notebook, tablet,
    // convertible, detachable. 0 means the kernel reported no chassis type.
    readonly property var portableChassisTypes: [8, 9, 10, 11, 14, 30, 31, 32]

    // Read once at startup from /sys/class/dmi/id/chassis_type.
    property int chassisType: 0

    readonly property var display: UPower.displayDevice
    readonly property bool hasDisplay: !!root.display

    readonly property bool chassisPortable: root.portableChassisTypes.indexOf(root.chassisType) !== -1

    // True once UPower has answered. Before that, `isPresent` is still false
    // for a real battery, so the service must not conclude it is missing.
    readonly property bool upowerReady: root.hasDisplay && root.display.ready

    // Set after a short startup window so a laptop with no UPower daemon still
    // reports the missing battery instead of hiding the chip forever.
    property bool startupSettled: false

    // A usable internal battery: UPower reports the aggregate battery device
    // as physically present.
    readonly property bool present: root.upowerReady
        && root.display.isPresent
        && root.display.type === UPowerDeviceType.Battery

    // A laptop with no usable battery still needs the chip, so the missing
    // battery is visible instead of silently hiding the indicator. Waiting for
    // `upowerReady` or the startup window avoids a "missing" flash on every
    // shell start.
    readonly property bool expected: root.present
        || (root.chassisPortable && (root.upowerReady || root.startupSettled))

    // Quickshell exposes UPower's 0-100 Percentage as a 0.0-1.0 fraction
    // (DBusDataTransform<PowerPercentage>), so scale it back for the bar.
    readonly property int percentage: root.present
        ? Math.max(0, Math.min(100, Math.round(root.display.percentage * 100)))
        : 0

    readonly property bool charging: root.present
        && (root.display.state === UPowerDeviceState.Charging
            || root.display.state === UPowerDeviceState.PendingCharge)

    // AC power is connected. This is deliberately separate from `charging`:
    // a battery that is already full keeps UPower at FullyCharged, so the
    // charge state alone would miss plugging in at 100%. The AC flag tells the
    // shell that a charger started supplying power.
    readonly property bool plugged: root.present && !UPower.onBattery

    // Emitted once when the charger starts supplying power, never for the
    // state already present at shell start. Battery.qml turns it into the
    // one-shot charge bloom.
    signal chargerConnected()

    // Priming: the first state after UPower becomes ready is recorded
    // silently, so logging in (or restarting the shell) with the charger
    // already plugged in does not replay the animation. A battery that
    // disappears resets the record, so reinserting it while the charger is
    // still connected is not mistaken for a new plug-in.
    property bool chargerStateKnown: false
    property bool lastPlugged: false
    property bool chargerPrimeQueued: false

    function trackChargerState() {
        if (!root.upowerReady)
            return;

        if (!root.present) {
            root.chargerStateKnown = false;
            root.lastPlugged = false;
            return;
        }

        if (!root.chargerStateKnown) {
            // `present`, `upowerReady` and `plugged` can settle in either
            // order on startup, so the baseline is recorded one event-loop
            // turn later, after the bindings have their final values.
            if (!root.chargerPrimeQueued) {
                root.chargerPrimeQueued = true;
                Qt.callLater(root.primeChargerState);
            }
            return;
        }

        if (root.plugged && !root.lastPlugged)
            root.chargerConnected();

        root.lastPlugged = root.plugged;
    }

    function primeChargerState() {
        root.chargerPrimeQueued = false;

        if (root.chargerStateKnown || !root.upowerReady || !root.present)
            return;

        root.lastPlugged = root.plugged;
        root.chargerStateKnown = true;
    }

    onPluggedChanged: root.trackChargerState()
    onUpowerReadyChanged: root.trackChargerState()

    // Low enough that the bar should warn: red icon/text while unplugged.
    readonly property bool low: root.present && !root.charging && root.percentage <= 15

    // One-shot warning thresholds, highest first. 15% matches the red bar
    // chip; 10% and 5% escalate to a more urgent chime.
    readonly property var lowBatteryThresholds: [15, 10, 5]

    // Emitted once per crossed threshold and discharge cycle. EventSoundService
    // turns it into the matching sound.
    signal lowBattery(int threshold)

    property var announcedThresholds: []
    // Swallows the state already present at shell start, so logging in at 8%
    // does not chime before the user changed anything.
    property bool batterySoundPrimed: false

    // One handler for both consumers of `present`: the charger record must
    // reset when the pack disappears, and the low-battery thresholds must be
    // cleared as well. QML rejects a second `onPresentChanged` block in the
    // same object with "Property value set multiple times".
    onPresentChanged: {
        root.trackChargerState();
        root.evaluateLowBattery();
    }
    onPercentageChanged: root.evaluateLowBattery()
    onChargingChanged: root.evaluateLowBattery()

    function evaluateLowBattery() {
        if (!root.lowBatteryThresholds)
            return;

        if (!root.present) {
            root.announcedThresholds = [];
            root.batterySoundPrimed = false;
            return;
        }

        // UPower can report a ready device with a placeholder 0 while it
        // settles; do not prime the thresholds from that value.
        if (root.percentage <= 0)
            return;

        if (!root.batterySoundPrimed) {
            root.batterySoundPrimed = true;
            const initial = [];
            for (let i = 0; i < root.lowBatteryThresholds.length; i++) {
                const threshold = root.lowBatteryThresholds[i];
                if (root.percentage <= threshold)
                    initial.push(threshold);
            }
            root.announcedThresholds = initial;
            return;
        }

        if (root.charging) {
            // Only a charge above the highest warning threshold starts a new
            // discharge cycle; replugging at 12% must not replay the 15% chime.
            if (root.percentage > root.lowBatteryThresholds[0])
                root.announcedThresholds = [];
            return;
        }

        let crossed = 0;
        for (let i = 0; i < root.lowBatteryThresholds.length; i++) {
            const threshold = root.lowBatteryThresholds[i];
            if (root.percentage <= threshold
                    && root.announcedThresholds.indexOf(threshold) === -1)
                crossed = threshold;
        }

        if (crossed <= 0)
            return;

        // A drop that skips several thresholds (e.g. waking from sleep) warns
        // once, at the most urgent level, instead of playing every chime.
        const announced = root.announcedThresholds.slice();
        for (let i = 0; i < root.lowBatteryThresholds.length; i++) {
            const threshold = root.lowBatteryThresholds[i];
            if (threshold >= crossed && announced.indexOf(threshold) === -1)
                announced.push(threshold);
        }
        root.announcedThresholds = announced;
        root.lowBattery(crossed);
    }

    property Timer settleTimer: Timer {
        interval: 6000
        running: !root.upowerReady
        onTriggered: root.startupSettled = true
    }

    property FileView chassisReader: FileView {
        path: ShellPaths.chassisType
        printErrors: false

        onLoaded: {
            const value = parseInt(text().trim(), 10);
            root.chassisType = isNaN(value) ? 0 : value;
        }
        onLoadFailed: root.chassisType = 0
    }
}
