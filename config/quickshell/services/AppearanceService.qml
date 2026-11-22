pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Matugen scheme settings shown on the Appearance page.
//
// The choices are persisted as one-line JSON in
// ~/.cache/quickshell/appearance.json so generate-colors.sh (and the
// toggle-theme.sh fallback) can read the same intent:
//   {"type":"scheme-neutral","contrast":0,"mode":"dark"}
//
// `mode` is auto/light/dark. Auto follows sunrise and sunset for the location
// detected by HyprsunsetService: daytime gets the light palette and night the
// dark one. An explicit mode (and every resolved auto switch) is also written
// to ~/.cache/current_theme by generate-colors.sh, so the bar's theme toggle
// and GTK/KDE stay in sync. Changes regenerate the palette through
// generate-colors.sh, which writes colors.json in place; Colors.qml watches
// that file, so the shell crossfades to the new palette without a restart.
// `crossfade` is the only non-Matugen choice here: it lets Colors.qml apply
// the palette instantly on slow machines.
QtObject {
    id: root

    // ── Choices ────────────────────────────────────────────────────────────
    // Values are matugen's --type values; the UI drops the "scheme-" prefix.
    readonly property var schemeTypes: [
        { value: "scheme-content", label: "Content" },
        { value: "scheme-expressive", label: "Expressive" },
        { value: "scheme-fidelity", label: "Fidelity" },
        { value: "scheme-fruit-salad", label: "Fruit salad" },
        { value: "scheme-monochrome", label: "Monochrome" },
        { value: "scheme-neutral", label: "Neutral" },
        { value: "scheme-rainbow", label: "Rainbow" },
        { value: "scheme-tonal-spot", label: "Tonal spot" },
        { value: "scheme-vibrant", label: "Vibrant" },
        { value: "scheme-smart", label: "Smart" },
    ]

    // Defaults preserve the pre-Appearance pipeline (neutral, standard
    // contrast) until the user saves a choice.
    property string schemeType: "scheme-neutral"
    property real contrast: 0
    // Derived from ~/.cache/current_theme while no saved state exists, so the
    // page reflects the live theme instead of pretending Auto is selected.
    property string mode: "dark"
    // Crossfade of the generated palette, read by Colors.qml. On by default;
    // turning it off keeps every generated color but applies it instantly,
    // which is the escape hatch for slow machines.
    property bool crossfade: true

    readonly property string schemeLabel: root.labelFor(root.schemeType)

    // True once a valid "mode" was loaded from or written to the state file.
    // Until then the current theme file decides which mode is highlighted.
    property bool hasSavedMode: false
    property bool stateDirReady: false

    // Resolved desktop theme, watched from ~/.cache/current_theme. `auto`
    // compares against this so sunrise/sunset only regenerate when the
    // palette actually has to change.
    property string currentTheme: "dark"
    property bool themeLoaded: false
    property date now: new Date()

    readonly property bool autoActive: root.mode === "auto"
    readonly property bool autoPaused: root.autoActive
        && !HyprsunsetService.sunTimesAvailable

    // One-line explanation under the mode chips. When Auto is off it explains
    // what Auto does; when it is on it names the next switch, like the
    // night-light schedule card.
    readonly property string autoStatusText: {
        if (!root.autoActive)
            return "Auto follows sunrise and sunset for your location";

        if (HyprsunsetService.locationRefreshing)
            return "Detecting location…";

        if (!HyprsunsetService.sunTimesAvailable)
            return "Location unavailable — refresh to resume Auto";

        const times = HyprsunsetService.sunTimes;
        if (!times.sunrise || !times.sunset)
            return "Sunrise/sunset unavailable for this date";

        const timestamp = root.now.getTime();
        if (timestamp < times.sunrise.getTime())
            return "Dark until " + HyprsunsetService.formatDate(times.sunrise);

        if (timestamp < times.sunset.getTime())
            return "Light until " + HyprsunsetService.formatDate(times.sunset);

        const tomorrow = new Date(root.now);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const next = HyprsunsetService.computeSunTimes(tomorrow,
            HyprsunsetService.latitude, HyprsunsetService.longitude);

        return next.sunrise
            ? "Dark until " + HyprsunsetService.formatDate(next.sunrise)
                + " tomorrow"
            : "Dark until sunrise";
    }

    // Debounced regeneration state. `regenerating` stays true through the
    // debounce window, an in-flight matugen run and a queued rerun.
    property bool regenerating: false
    property bool regenerateQueued: false

    // Per-scheme palette previews for the scheme picker. The worker caches by
    // wallpaper, mode and contrast, so reopening the page is instant.
    property var palettePreviews: ({})
    property bool previewsLoading: false
    property bool previewsVisible: false
    property bool previewsQueued: false
    property string previewsError: ""

    function labelFor(value) {
        for (let i = 0; i < root.schemeTypes.length; i++) {
            if (root.schemeTypes[i].value === value)
                return root.schemeTypes[i].label;
        }
        return value;
    }

    function isSchemeType(value) {
        for (let i = 0; i < root.schemeTypes.length; i++) {
            if (root.schemeTypes[i].value === value)
                return true;
        }
        return false;
    }

    function isMode(value) {
        return value === "auto" || value === "light" || value === "dark";
    }

    function clampContrast(value) {
        const number = Number(value);
        if (!isFinite(number))
            return root.contrast;

        return Math.max(-1, Math.min(1, Math.round(number * 100) / 100));
    }

    // Resolved light/dark for Auto, or "" when the sun times are not known.
    // Daylight starts at sunrise and ends at sunset for the detected location.
    function autoTargetMode() {
        if (!HyprsunsetService.sunTimesAvailable)
            return "";

        const times = HyprsunsetService.sunTimes;
        if (!times.sunrise || !times.sunset)
            return "";

        const timestamp = root.now.getTime();
        return timestamp >= times.sunrise.getTime()
            && timestamp < times.sunset.getTime() ? "light" : "dark";
    }

    // Mode actually passed to matugen: Auto resolves to light/dark, while an
    // unknown schedule keeps the last resolved theme so colors never jump.
    function effectiveMode() {
        if (!root.autoActive)
            return root.mode;

        const target = root.autoTargetMode();
        return target !== "" ? target : root.currentTheme;
    }

    // Called on the 30 s tick, when the location arrives and when the script
    // writes the resolved theme. Only a real boundary change regenerates.
    function syncAutoMode() {
        if (!root.autoActive || !root.themeLoaded)
            return;

        const target = root.autoTargetMode();
        if (target === "" || target === root.currentTheme)
            return;

        root.regenerating = true;
        root.regenerateTimer.restart();
        root.schedulePreviews();
    }

    // ── Palette previews ───────────────────────────────────────────────────
    // The Appearance page marks itself visible so the 10-scheme preview worker
    // runs only while the picker is on screen (and immediately, from cache,
    // each time it opens again).
    function setPreviewsVisible(value) {
        if (root.previewsVisible === value)
            return;

        root.previewsVisible = value;
        if (value)
            root.refreshPreviews();
    }

    function schedulePreviews() {
        if (!root.previewsVisible)
            return;

        root.previewsTimer.restart();
    }

    function refreshPreviews() {
        if (!root.previewsVisible)
            return;

        if (root.previewsProcess.running) {
            root.previewsQueued = true;
            return;
        }

        root.previewsQueued = false;
        root.previewsLoading = true;
        root.previewsError = "";
        root.previewsProcess.command = [
            "sh",
            ShellPaths.palettePreviews,
            root.effectiveMode(),
            String(root.contrast),
            ShellPaths.palettePreviewsCache,
        ];
        root.previewsProcess.running = true;
    }

    function loadPreviews(text) {
        const content = text.trim();
        if (content === "")
            return;

        try {
            const parsed = JSON.parse(content);
            if (parsed && parsed.palettes && typeof parsed.palettes === "object") {
                root.palettePreviews = parsed.palettes;
            } else {
                root.previewsError = "Invalid palette preview data";
            }
        } catch (error) {
            root.previewsError = "Invalid palette preview data";
            console.warn("AppearanceService: invalid palette preview JSON:", error);
        }
    }

    // ── Setters ────────────────────────────────────────────────────────────
    function setSchemeType(value) {
        if (!root.isSchemeType(value) || value === root.schemeType)
            return;

        root.schemeType = value;
        root.commit();
    }

    function setContrast(value) {
        const next = root.clampContrast(value);
        if (next === root.contrast)
            return;

        root.contrast = next;
        root.commit();
    }

    function setMode(value) {
        if (!root.isMode(value) || value === root.mode)
            return;

        root.mode = value;
        root.commit();
    }

    // Palette crossfade is a Colors.qml option, not a Matugen input: persist it
    // without regenerating the palette.
    function setCrossfade(value) {
        if (root.crossfade === value)
            return;

        root.crossfade = value;
        root.saveTimer.restart();
    }

    function commit() {
        root.hasSavedMode = true;
        root.now = new Date();
        root.saveTimer.restart();
        root.regenerating = true;
        root.regenerateTimer.restart();
        root.schedulePreviews();
    }

    // ── Persistence ────────────────────────────────────────────────────────
    function loadState() {
        const content = root.stateFile.text();
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);

                if (root.isSchemeType(parsed.type))
                    root.schemeType = parsed.type;

                if (parsed.contrast !== undefined && parsed.contrast !== null) {
                    const parsedContrast = Number(parsed.contrast);
                    if (isFinite(parsedContrast))
                        root.contrast = root.clampContrast(parsedContrast);
                }

                if (root.isMode(parsed.mode)) {
                    root.mode = parsed.mode;
                    root.hasSavedMode = true;
                }

                if (typeof parsed.crossfade === "boolean")
                    root.crossfade = parsed.crossfade;
            } catch (error) {
                console.warn("AppearanceService: invalid state file:", error);
            }
        }
    }

    function writeState() {
        if (!root.stateDirReady)
            return;

        // Keep this a one-line object with exactly these keys:
        // generate-colors.sh and toggle-theme.sh read it with sed.
        root.stateFile.setText(JSON.stringify({
            type: root.schemeType,
            contrast: Number(root.contrast.toFixed(2)),
            mode: root.mode,
            crossfade: root.crossfade,
        }));
    }

    // ── Regeneration ───────────────────────────────────────────────────────
    function regenerate() {
        if (root.regenerateProcess.running) {
            root.regenerateQueued = true;
            return;
        }

        root.regenerateQueued = false;
        root.regenerating = true;
        root.regenerateProcess.environment = {
            KOLIR_MATUGEN_TYPE: root.schemeType,
            KOLIR_MATUGEN_CONTRAST: String(root.contrast),
            KOLIR_MATUGEN_MODE: root.effectiveMode(),
        };
        root.regenerateProcess.running = true;
    }

    // Grow the cache directory and seed an empty state file once, so FileView
    // does not log a read failure on first run. An empty file means "no saved
    // choice": the live current_theme then decides the highlighted mode.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "appearance", ShellPaths.quickshellCache, ShellPaths.appearanceState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("AppearanceService: cannot create",
                    ShellPaths.appearanceState);
                return;
            }

            root.stateDirReady = true;
        }
    }

    property FileView stateFile: FileView {
        path: root.stateDirReady ? ShellPaths.appearanceState : ""
        atomicWrites: true
        // toggle-theme.sh rewrites the mode when the bar toggle is used, so
        // reload the file instead of trusting the in-memory copy.
        watchChanges: true

        onFileChanged: this.reload()
        onLoaded: root.loadState()
    }

    // Live resolved theme, also used as the Auto fallback while the location
    // or the sun times are unavailable.
    property FileView themeFile: FileView {
        path: ShellPaths.currentTheme
        watchChanges: true

        onFileChanged: this.reload()

        onLoaded: {
            const theme = this.text().trim();
            if (theme !== "light" && theme !== "dark")
                return;

            root.currentTheme = theme;
            root.themeLoaded = true;

            if (!root.hasSavedMode)
                root.mode = theme;
            else if (root.autoActive)
                root.syncAutoMode();
        }
    }

    // Location and solar times come from HyprsunsetService, the same source
    // the night-light schedule uses. Auto resumes as soon as they arrive.
    property Connections hyprsunsetConnection: Connections {
        target: HyprsunsetService

        function onSunTimesAvailableChanged() {
            root.syncAutoMode();
        }
    }

    property Timer autoTimer: Timer {
        interval: 30000
        repeat: true
        running: root.autoActive
        triggeredOnStart: true

        onTriggered: {
            root.now = new Date();
            root.syncAutoMode();
        }
    }

    property Timer saveTimer: Timer {
        interval: 300
        repeat: false

        onTriggered: root.writeState()
    }

    property Timer regenerateTimer: Timer {
        interval: 400
        repeat: false

        onTriggered: root.regenerate()
    }

    property Timer previewsTimer: Timer {
        interval: 600
        repeat: false

        onTriggered: root.refreshPreviews()
    }

    property Process previewsProcess: Process {
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.loadPreviews(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    root.previewsError = output;
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.previewsLoading = false;

            if (exitCode !== 0) {
                if (root.previewsError === "")
                    root.previewsError = "Palette preview unavailable";
                console.warn("AppearanceService: palette previews failed: "
                    + root.previewsError);
            }

            if (root.previewsQueued) {
                root.previewsQueued = false;
                root.refreshPreviews();
            }
        }
    }

    property Process regenerateProcess: Process {
        command: ["zsh", ShellPaths.hyprScripts + "/generate-colors.sh"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    console.warn("AppearanceService: " + output);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("AppearanceService: generate-colors.sh exited with",
                    exitCode);

            if (root.regenerateQueued) {
                root.regenerateQueued = false;
                root.regenerate();
            } else {
                root.regenerating = false;
            }
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "appearance"

        function setType(value: string): void {
            root.setSchemeType(value);
        }

        function setContrast(value: string): void {
            root.setContrast(Number(value));
        }

        function setMode(value: string): void {
            root.setMode(value);
        }

        function setCrossfade(value: string): void {
            root.setCrossfade(value === "true" || value === "on" || value === "1");
        }

        function regenerate(): void {
            root.regenerateTimer.stop();
            root.regenerate();
        }

        function status(): string {
            return JSON.stringify({
                type: root.schemeType,
                contrast: root.contrast,
                mode: root.mode,
                resolved: root.effectiveMode(),
                crossfade: root.crossfade,
                auto: root.autoActive,
                autoPaused: root.autoPaused,
                autoStatus: root.autoStatusText,
                regenerating: root.regenerating,
                saved: root.hasSavedMode,
            });
        }
    }
}
