pragma Singleton
import QtQuick
import Quickshell.Io
import "vpn/Tailscale.js" as Tailscale

// Tailscale state for the Internet page's Tailscale section.
//
// The daemon is the only source of truth: `tailscale status --json` carries the
// backend state, the node identity, the peers and the exit node, while
// `systemctl is-active tailscaled` explains the common "binary installed but
// the service was never enabled" case. Nothing here runs sudo — a privilege
// refusal becomes a `hint` the card can show verbatim instead of a failing
// command the user cannot see.
//
// Two timers: a slow one re-probes while the binary is missing (installing
// tailscale later must not need a shell restart), and the normal poll that only
// runs once the binary answered. A page opening calls setWatching(true) and
// drops the interval to 5 s.
QtObject {
    id: root

    property bool installed: false
    property bool daemonRunning: false

    property string backendState: ""
    readonly property bool connected: root.backendState === "Running"

    property string hostName: ""
    property string dnsName: ""
    property string exitNode: ""
    property string exitNodeId: ""

    property var ips: []
    property var exitNodes: []
    property var health: []
    property int peersOnline: 0
    property int peersTotal: 0

    property bool busy: false
    property string lastError: ""
    property string hint: ""

    property bool watching: false

    // True while `lastError` came from the status read itself, so a recovered
    // daemon clears that message without wiping an action failure the user
    // still has to read.
    property bool statusError: false
    // A refused command is a persistent condition (no operator rights), so the
    // hint survives the polls that follow until a command finally succeeds.
    property bool permissionHint: false

    // One read at a time: overlapping timer ticks would publish a half-read
    // model and make the card flicker.
    property bool refreshing: false
    property bool statusDone: false
    property bool daemonDone: false

    // stdout/stderr text of the running processes, keyed by stream. The
    // processes stay plain `Process` objects, so every handler reads and clears
    // its stream through these two helpers.
    property var streams: ({})
    property string actionLabel: ""

    function appendStream(key, line) {
        root.streams[key] = (root.streams[key] || "") + line + "\n";
    }

    // Returns the collected text and empties the slot, so a retried process
    // never sees a previous run's tail.
    function takeStream(key) {
        const text = root.streams[key] || "";
        root.streams[key] = "";
        return text;
    }

    function firstLine(text) {
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line !== "")
                return line;
        }
        return "";
    }

    function setWatching(value) {
        root.watching = value === true;
    }

    // Priority: a refused command explains why nothing works, then a login
    // that has to happen in a terminal, then a daemon that is not running.
    function recomputeHint() {
        if (!root.installed) {
            root.hint = "";
            return;
        }
        if (root.permissionHint) {
            root.hint = "Grant access: sudo tailscale set --operator=$USER";
            return;
        }
        if (root.backendState === "NeedsLogin") {
            root.hint = "Sign in from a terminal: sudo tailscale up";
            return;
        }
        if (!root.daemonRunning) {
            root.hint = "Start the daemon: sudo systemctl enable --now tailscaled";
            return;
        }
        root.hint = "";
    }

    function clearModel() {
        root.backendState = "";
        root.hostName = "";
        root.dnsName = "";
        root.exitNode = "";
        root.exitNodeId = "";
        root.ips = [];
        root.exitNodes = [];
        root.health = [];
        root.peersOnline = 0;
        root.peersTotal = 0;
    }

    function applyStatus(parsed) {
        root.backendState = parsed.backendState;
        root.hostName = parsed.hostName;
        root.dnsName = parsed.dnsName;
        root.ips = parsed.ips;
        root.exitNodes = parsed.exitNodes;
        root.health = parsed.health;
        root.peersOnline = parsed.peersOnline;
        root.peersTotal = parsed.peersTotal;
        root.exitNode = parsed.exitNode ? parsed.exitNode.name : "";
        root.exitNodeId = parsed.exitNode ? parsed.exitNode.id : "";

        if (root.statusError) {
            root.statusError = false;
            root.lastError = "";
        }
    }

    // ── Reading ────────────────────────────────────────────────────────────
    function refresh() {
        if (root.refreshing)
            return;

        root.refreshing = true;
        root.statusDone = false;
        root.daemonDone = false;

        // Only the read streams belong to this refresh; a still-running action
        // keeps its buffer so its stderr can still explain a failure.
        root.takeStream("status");
        root.takeStream("statusError");
        root.takeStream("daemon");

        root.statusProc.running = true;
        root.daemonProc.running = true;
    }

    function finishRefresh() {
        if (!root.statusDone || !root.daemonDone)
            return;
        root.recomputeHint();
        root.refreshing = false;
    }

    // ── Actions ────────────────────────────────────────────────────────────
    function startAction(command, label) {
        if (root.busy)
            return false;

        root.busy = true;
        root.lastError = "";
        root.statusError = false;
        root.actionLabel = label;
        root.actionProc.command = command;
        root.actionProc.running = true;
        return true;
    }

    function up() {
        root.startAction(["tailscale", "up"], "Could not bring Tailscale up");
    }

    function down() {
        root.startAction(["tailscale", "down"], "Could not bring Tailscale down");
    }

    // An empty name clears the exit node, which tailscale spells as an empty
    // `--exit-node=` value rather than an omitted flag.
    function setExitNode(name) {
        const node = String(name || "");
        root.startAction(
            ["tailscale", "set", "--exit-node=" + node],
            "Could not change the exit node");
    }

    // ── Processes ──────────────────────────────────────────────────────────
    property Process statusProc: Process {
        command: ["tailscale", "status", "--json"]
        stdout: SplitParser {
            onRead: line => root.appendStream("status", line)
        }
        stderr: SplitParser {
            onRead: line => root.appendStream("statusError", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("status");
            const message = root.takeStream("statusError");
            const lower = message.toLowerCase();

            if (exitCode === 0) {
                root.installed = true;
                const parsed = Tailscale.parseStatus(text);
                if (parsed === null) {
                    root.statusError = true;
                    root.lastError = "Could not read the Tailscale status";
                } else {
                    root.applyStatus(parsed);
                }
            } else if (exitCode === 127
                || lower.indexOf("command not found") >= 0
                || lower.indexOf("executable file not found") >= 0) {
                // Not installed: the slow probe timer keeps looking for it.
                root.installed = false;
                root.clearModel();
            } else if (lower.indexOf("failed to connect") >= 0
                || lower.indexOf("appear to be running") >= 0
                || lower.indexOf("not running") >= 0) {
                // The binary is there, the daemon is not: keep the section
                // visible and explain how to start it.
                root.installed = true;
                root.daemonRunning = false;
                root.clearModel();
            } else {
                root.installed = true;
                root.statusError = true;
                root.lastError = root.firstLine(message)
                    || "Could not read the Tailscale status";
                root.clearModel();
            }

            root.statusDone = true;
            root.finishRefresh();
        }
    }

    property Process daemonProc: Process {
        command: ["systemctl", "is-active", "tailscaled"]
        stdout: SplitParser {
            onRead: line => root.appendStream("daemon", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("daemon").trim();

            // `is-active` prints the state and exits non-zero while it is not
            // active, so the text, not the exit code, is the answer.
            root.daemonRunning = text === "active";
            root.daemonDone = true;
            root.finishRefresh();
        }
    }

    property Process actionProc: Process {
        stdout: SplitParser {
            onRead: line => root.appendStream("action", line)
        }
        stderr: SplitParser {
            onRead: line => root.appendStream("action", line)
        }
        onExited: (exitCode, exitStatus) => {
            const text = root.takeStream("action");
            const label = root.actionLabel;
            root.actionLabel = "";
            root.busy = false;

            if (exitCode === 0) {
                root.permissionHint = false;
            } else {
                const lower = text.toLowerCase();
                if (lower.indexOf("permission denied") >= 0
                    || lower.indexOf("access denied") >= 0
                    || lower.indexOf("operator") >= 0) {
                    root.permissionHint = true;
                } else {
                    root.lastError = root.firstLine(text) || label;
                }
            }

            root.refresh();
        }
    }

    // Normal poll: only runs while the binary answered, and speeds up while a
    // page is watching.
    property Timer poll: Timer {
        interval: root.watching ? 5000 : 15000
        repeat: true
        running: root.installed
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    // Slow probe while tailscale is not installed, so installing it later
    // needs neither a shell restart nor a manual refresh.
    property Timer probe: Timer {
        interval: 60000
        repeat: true
        running: !root.installed
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    property IpcHandler ipc: IpcHandler {
        target: "tailscale"

        function status(): string {
            return JSON.stringify({
                installed: root.installed,
                daemonRunning: root.daemonRunning,
                backendState: root.backendState,
                connected: root.connected,
                hostName: root.hostName,
                dnsName: root.dnsName,
                ips: root.ips,
                exitNode: root.exitNode,
                exitNodeId: root.exitNodeId,
                exitNodes: root.exitNodes,
                peersOnline: root.peersOnline,
                peersTotal: root.peersTotal,
                health: root.health,
                hint: root.hint,
                busy: root.busy,
                lastError: root.lastError,
            });
        }

        function up(): string {
            if (root.busy)
                return "busy";
            root.up();
            return "starting Tailscale";
        }

        function down(): string {
            if (root.busy)
                return "busy";
            root.down();
            return "stopping Tailscale";
        }

        function setExitNode(name: string): string {
            if (root.busy)
                return "busy";
            root.setExitNode(name);
            return String(name || "") === ""
                ? "clearing the exit node"
                : "using exit node " + name;
        }

        function refresh(): string {
            if (root.refreshing)
                return "busy";
            root.refresh();
            return "refreshing";
        }
    }
}
