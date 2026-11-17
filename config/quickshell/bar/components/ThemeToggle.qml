import "../../theme"
import Quickshell
import Quickshell.Io
import QtQuick

// Theme switch as an M3 icon button.
IconButton {
    id: root

    property string currentTheme: "dark"

    icon: root.currentTheme === "light" ? Icons.lightMode : Icons.darkMode
    iconColor: Colors.onSurface
    iconSize: Dimensions.icon.large

    onCurrentThemeChanged: themePop.restart()

    SequentialAnimation {
        id: themePop
        NumberAnimation {
            target: root.iconItem
            property: "scale"
            from: 0.7
            to: 1.0
            duration: 180
            easing.type: Easing.OutBack
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/current_theme"
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            const t = this.text().trim();
            if (t === "light" || t === "dark")
                root.currentTheme = t;
        }
    }

    onClicked: toggleProc.running = true

    Process {
        id: toggleProc
        command: ["sh", Quickshell.env("HOME") + "/.config/hypr/scripts/toggle-theme.sh"]
        running: false
    }
}
