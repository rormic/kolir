pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Font choices for the whole desktop, shown in Settings → Fonts.
//
// The shell only stores the intent in ~/.cache/quickshell/fonts.json:
//   {"ui":"","terminal":"","obsidian":false}
//
// An empty family means "never touched": Typography.qml keeps its built-in
// default and the helper perturbs no existing Foot file. Once a family is
// chosen it is rendered by scripts/font-sync.py into:
//   * ~/.config/foot/font.ini (included by the managed Foot loader)
//   * <vault>/.obsidian/snippets/kolir-font.css when the Obsidian switch is on
//
// Quickshell itself reads this singleton through Typography, so a new family
// repaints the bar and launcher immediately. Foot only picks the file up for
// new windows. The lock screen deliberately keeps its Google Sans Flex clock:
// its width, stretch and round-terminal mix is designed around that family.
QtObject {
    id: root

    readonly property string defaultInterfaceFont: "Google Sans"
    readonly property string defaultTerminalFont: "Google Sans Code NF"

    property string interfaceFont: ""
    property string terminalFont: ""
    property bool obsidianFollows: false

    // The values Typography and the helper actually use. The distinction from
    // the raw properties matters: an untouched empty family must not rewrite
    // a hand-written Foot config.
    readonly property string resolvedInterfaceFont: root.interfaceFont !== ""
        ? root.interfaceFont
        : root.defaultInterfaceFont
    readonly property string resolvedTerminalFont: root.terminalFont !== ""
        ? root.terminalFont
        : root.defaultTerminalFont

    // Installed families, loaded lazily when the Fonts page opens. Each entry
    // is {family, mono}; `mono` comes from fontconfig's spacing property so
    // the terminal picker can hide proportional faces.
    property var fonts: []
    property bool fontsLoaded: false
    property bool fontsLoading: false
    property string fontsError: ""

    // Persistence and the one-shot helper process.
    property bool stateReady: false
    property bool stateLoaded: false
    property bool applying: false
    property bool applyQueued: false
    property bool queuedCleanObsidian: false
    property string applyError: ""
    property string obsidianVault: ""
    property string obsidianError: ""

    function maxFonts() {
        return 2000;
    }

    function ensureFonts(force) {
        if (root.fontsLoading)
            return;

        if (root.fontsLoaded && !force)
            return;

        root.fontsLoading = true;
        root.fontsError = "";
        root.listProcess.command = ["python3", ShellPaths.fontSyncScript, "list"];
        root.listProcess.running = true;
    }

    // ── Setters ────────────────────────────────────────────────────────────
    function setInterfaceFont(value) {
        const next = typeof value === "string" ? value.trim() : "";
        if (next === root.interfaceFont)
            return;

        root.interfaceFont = next;
        root.saveTimer.restart();
        root.applyTimer.restart();
    }

    function setTerminalFont(value) {
        const next = typeof value === "string" ? value.trim() : "";
        if (next === root.terminalFont)
            return;

        root.terminalFont = next;
        root.saveTimer.restart();
        root.applyTimer.restart();
    }

    function setObsidianFollows(value) {
        if (root.obsidianFollows === value)
            return;

        root.obsidianFollows = value;
        root.saveTimer.restart();
        // Turning the switch off also removes the generated snippet; turning
        // it on just rewrites it with the current families.
        root.applyFonts(!value);
    }

    function resetInterfaceFont() {
        root.setInterfaceFont(root.defaultInterfaceFont);
    }

    function resetTerminalFont() {
        root.setTerminalFont(root.defaultTerminalFont);
    }

    // ── Persistence ────────────────────────────────────────────────────────
    function loadState() {
        const content = root.stateFile.text();
        if (content && content.trim() !== "") {
            try {
                const parsed = JSON.parse(content);
                if (typeof parsed.ui === "string")
                    root.interfaceFont = parsed.ui.trim();
                if (typeof parsed.terminal === "string")
                    root.terminalFont = parsed.terminal.trim();
                if (typeof parsed.obsidian === "boolean")
                    root.obsidianFollows = parsed.obsidian;
            } catch (error) {
                console.warn("FontService: invalid state file:", error);
            }
        }

        if (!root.stateLoaded) {
            root.stateLoaded = true;
            // Render once after login so a saved choice survives a shell
            // restart even when the helper files were edited or lost.
            root.applyTimer.restart();
        }
    }

    function writeState() {
        if (!root.stateReady)
            return;

        root.stateFile.setText(JSON.stringify({
            ui: root.interfaceFont,
            terminal: root.terminalFont,
            obsidian: root.obsidianFollows,
        }));
    }

    // ── Helper ─────────────────────────────────────────────────────────────
    function applyFonts(cleanObsidian) {
        const clean = cleanObsidian === true;

        if (!root.stateReady) {
            root.applyQueued = true;
            root.queuedCleanObsidian = root.queuedCleanObsidian || clean;
            return;
        }

        if (root.applyProcess.running) {
            root.applyQueued = true;
            root.queuedCleanObsidian = root.queuedCleanObsidian || clean;
            return;
        }

        root.applyQueued = false;
        root.queuedCleanObsidian = false;
        root.applying = true;
        root.applyError = "";

        const command = [
            "python3",
            ShellPaths.fontSyncScript,
            "apply",
            "--ui", root.resolvedInterfaceFont,
            "--terminal", root.resolvedTerminalFont,
            "--foot", root.terminalFont !== "" ? "on" : "off",
            "--obsidian", root.obsidianFollows ? "on" : "off",
        ];
        if (clean)
            command.push("--clean-obsidian");

        root.applyProcess.command = command;
        root.applyProcess.running = true;
    }

    function parseList(text) {
        const content = text.trim();
        if (content === "")
            return;

        try {
            const parsed = JSON.parse(content);
            if (parsed && parsed.ok === false && typeof parsed.error === "string") {
                root.fontsError = parsed.error;
                return;
            }
            if (parsed && Array.isArray(parsed.fonts)) {
                root.fonts = parsed.fonts.slice(0, root.maxFonts());
            } else {
                root.fontsError = "Invalid font list";
            }
        } catch (error) {
            root.fontsError = "Invalid font list";
            console.warn("FontService: invalid font list:", error);
        }
    }

    function parseApply(text) {
        const content = text.trim();
        if (content === "")
            return;

        try {
            const parsed = JSON.parse(content);
            if (!parsed || typeof parsed !== "object") {
                root.applyError = "Invalid font helper answer";
                return;
            }

            const obsidian = parsed.obsidian;
            if (obsidian && typeof obsidian === "object") {
                root.obsidianVault = typeof obsidian.vault === "string"
                    ? obsidian.vault
                    : "";
                root.obsidianError = typeof obsidian.error === "string"
                    ? obsidian.error
                    : "";
            }

            const errors = [];
            if (parsed.foot && parsed.foot.ok === false && parsed.foot.error)
                errors.push(parsed.foot.error);
            if (parsed.foot && parsed.foot.loader
                    && parsed.foot.loader.ok === false
                    && parsed.foot.loader.error)
                errors.push(parsed.foot.loader.error);

            root.applyError = errors.join(" · ");

            if (root.applyError === "" && parsed.ok === false
                    && typeof parsed.error === "string")
                root.applyError = parsed.error;
        } catch (error) {
            root.applyError = "Invalid font helper answer";
            console.warn("FontService: invalid helper answer:", error);
        }
    }

    // Grow the cache directory and seed an empty state file once, so FileView
    // does not log a read failure on first run.
    property Process ensureStateDir: Process {
        command: ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"",
            "fonts", ShellPaths.quickshellCache, ShellPaths.fontState]
        running: true

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("FontService: cannot create", ShellPaths.fontState);
                return;
            }

            root.stateReady = true;

            if (root.applyQueued) {
                const clean = root.queuedCleanObsidian;
                root.applyQueued = false;
                root.queuedCleanObsidian = false;
                root.applyFonts(clean);
            }
        }
    }

    property FileView stateFile: FileView {
        path: root.stateReady ? ShellPaths.fontState : ""
        atomicWrites: true
        watchChanges: true

        onFileChanged: this.reload()
        onLoaded: root.loadState()
    }

    property Timer saveTimer: Timer {
        interval: 250
        repeat: false

        onTriggered: root.writeState()
    }

    property Timer applyTimer: Timer {
        interval: 160
        repeat: false

        onTriggered: root.applyFonts(false)
    }

    property Process listProcess: Process {
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseList(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    root.fontsError = output;
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.fontsLoading = false;

            if (exitCode !== 0) {
                if (root.fontsError === "")
                    root.fontsError = "Font list unavailable";
                console.warn("FontService: font list failed: " + root.fontsError);
            } else {
                root.fontsLoaded = true;
            }
        }
    }

    property Process applyProcess: Process {
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseApply(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output !== "")
                    console.warn("FontService: " + output);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.applying = false;

            if (exitCode !== 0 && root.applyError === "")
                root.applyError = "Font helper failed";

            if (root.applyQueued) {
                const clean = root.queuedCleanObsidian;
                root.applyQueued = false;
                root.queuedCleanObsidian = false;
                root.applyFonts(clean);
            }
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "fonts"

        function setInterface(value: string): void {
            root.setInterfaceFont(value);
        }

        function setTerminal(value: string): void {
            root.setTerminalFont(value);
        }

        function setObsidian(value: string): void {
            root.setObsidianFollows(
                value === "true" || value === "on" || value === "1");
        }

        function list(): string {
            return JSON.stringify(root.fonts);
        }

        function apply(): void {
            root.applyTimer.stop();
            root.applyFonts(false);
        }

        function status(): string {
            return JSON.stringify({
                ui: root.interfaceFont,
                terminal: root.terminalFont,
                resolvedUi: root.resolvedInterfaceFont,
                resolvedTerminal: root.resolvedTerminalFont,
                obsidian: root.obsidianFollows,
                vault: root.obsidianVault,
                error: root.applyError !== ""
                    ? root.applyError
                    : (root.obsidianFollows ? root.obsidianError : ""),
                applying: root.applying,
                fonts: root.fonts.length,
            });
        }
    }
}
