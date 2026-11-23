import QtQuick
import Quickshell
import "../../theme"

// Resolves a Hyprland app class/app id to a desktop icon.
Item {
    id: root

    property string appClass: ""
    property int iconSize: Dimensions.icon.medium
    property string fallbackIcon: "application-x-executable"

    // Same QIcon rule as the launcher rows: request twice the drawn size in
    // device pixels so a 13–20 px slot still gets a 48 px theme asset that
    // Image scales down, instead of a 16 px PNG scaled up.
    readonly property int iconPixels: Math.max(2, Math.round(root.iconSize * Screen.devicePixelRatio * 2))

    readonly property bool ready: image.status === Image.Ready
    readonly property string source: {
        if (!root.appClass)
            return "";

        const icon = root.resolveIcon(root.appClass);
        if (icon.startsWith("/") || (icon !== "" && Quickshell.hasThemeIcon(icon)))
            return Quickshell.iconPath(icon, root.fallbackIcon);

        if (root.fallbackIcon !== "" && Quickshell.hasThemeIcon(root.fallbackIcon))
            return Quickshell.iconPath(root.fallbackIcon, "");

        return "";
    }

    // Resolution scans every desktop entry, so the result is memoised per class.
    // The desktop-entry count is part of the tag: the list loads after the first
    // bind at shell start, and a newly installed app must not keep a stale miss.
    readonly property int entriesRevision: DesktopEntries.applications.values.length
    property var iconCache: ({})

    implicitWidth: iconSize
    implicitHeight: iconSize

    function resolveIcon(appClass) {
        const revision = root.entriesRevision;
        const cached = root.iconCache[appClass];
        if (cached !== undefined && cached.revision === revision)
            return cached.icon;

        const icon = root.lookupIcon(appClass);
        root.iconCache[appClass] = { revision: revision, icon: icon };
        return icon;
    }

    function lookupIcon(appClass) {
        const cls = appClass.toLowerCase();
        const apps = DesktopEntries.applications.values;

        for (let i = 0; i < apps.length; i++) {
            const app = apps[i];
            const id = (app.id || "").toLowerCase();
            const name = (app.name || "").toLowerCase();
            const icon = (app.icon || "").toLowerCase();
            if (!icon)
                continue;
            if (id.includes(cls) || icon.includes(cls) || name.includes(cls) || cls.includes(icon))
                return app.icon;
        }

        const aliases = {
            "zen": "zen-browser",
            "zen-browser": "zen-browser",
            "foot": "foot",
            "steam": "steam",
            "org.gnome.nautilus": "org.gnome.Nautilus",
            "md.obsidian.obsidian": "obsidian",
            "obsidian": "obsidian",
            "kitty": "kitty",
            "alacritty": "alacritty",
            "firefox": "firefox",
            "google-chrome": "google-chrome",
            "chromium": "chromium",
            "code": "visual-studio-code",
            "telegramdesktop": "telegram",
            "org.telegram.desktop": "telegram",
            "discord": "discord",
            "vesktop": "vesktop",
            "spotify": "spotify",
            "aseprite": "aseprite"
        };

        return aliases[cls] || appClass;
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.iconPixels, root.iconPixels)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
    }
}
