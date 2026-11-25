pragma Singleton

import QtQuick
import Quickshell.Io

// One-shot session power actions. The power sheet owns the confirmation UI;
// this service only runs one command at a time and keeps the last failure so
// the sheet can stay open and explain it instead of closing silently.
QtObject {
    id: root

    property bool busy: false
    property string activeAction: ""
    property string lastError: ""
    property string stderrText: ""

    signal finished(string action)
    signal failed(string action, string message)

    function clearError() {
        root.lastError = "";
    }

    function run(action, command) {
        if (root.busy)
            return;

        root.busy = true;
        root.activeAction = action;
        root.lastError = "";
        root.stderrText = "";
        actionProc.command = command;
        actionProc.running = true;
    }

    function lock() {
        root.run("lock", ["loginctl", "lock-session"]);
    }

    // A manual suspend bypasses hypridle's before_sleep_cmd, so lock first and
    // give hyprlock a moment to paint before the machine sleeps. Turn the
    // displays back on after resume, like hypridle's after_sleep_cmd.
    function suspend() {
        root.run("suspend", ["sh", "-c",
            "loginctl lock-session; sleep 0.4; systemctl suspend; "
            + "hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})' || true"]);
    }

    function logout() {
        root.run("logout", ["hyprctl", "dispatch", "hl.dsp.exit()"]);
    }

    function reboot() {
        root.run("reboot", ["systemctl", "reboot"]);
    }

    function poweroff() {
        root.run("poweroff", ["systemctl", "poweroff"]);
    }

    property Process actionProc: Process {
        running: false

        stderr: StdioCollector {
            onStreamFinished: root.stderrText = text.trim()
        }

        onExited: (exitCode, exitStatus) => {
            const action = root.activeAction;
            root.busy = false;
            root.activeAction = "";

            if (exitCode === 0) {
                root.finished(action);
                return;
            }

            const firstLine = root.stderrText.split("\n")[0].trim();
            const message = firstLine !== ""
                ? firstLine
                : action + " failed";
            root.lastError = message;
            root.failed(action, message);
        }
    }
}
