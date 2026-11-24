pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

QtObject {
    id: root

    // Matugen rewrites colors.json in place while the shell is running (theme
    // toggle, new wallpaper, Appearance page). Every palette entry below
    // carries the same Behavior, so the shell crossfades to the new palette as
    // one transition instead of switching hard. Duration and easing are Motion
    // tokens; the Appearance page can turn the crossfade off on slow machines.
    //
    // The first load applies instantly: until colors.json has been applied the
    // constants below are the palette, and fading away from them would flash
    // the placeholder colors at every shell start. A failed or partial reload
    // (matugen still writing) keeps the last good palette, so the colors never
    // fall back to the defaults between two values.
    readonly property int paletteFade: root.paletteReady && AppearanceService.crossfade
        ? Motion.theme : 0
    // True after the first successful palette load.
    property bool paletteReady: false

    property color primary: "#86d6be"
    Behavior on primary { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    // Text colors start with "on", and `Behavior on onPrimary` is parsed as a
    // signal handler ("Cannot assign a value to a signal"), so their animated
    // value lives in a private twin and the public writable name is an alias.
    property color _onPrimary: "#00382c"
    Behavior on _onPrimary { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }
    property alias onPrimary: root._onPrimary

    property color primaryContainer: "#005141"
    Behavior on primaryContainer { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color _onPrimaryContainer: "#a2f2d9"
    Behavior on _onPrimaryContainer { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }
    property alias onPrimaryContainer: root._onPrimaryContainer

    property color secondary: "#a2cfc1"
    Behavior on secondary { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color tertiary: "#a9cbe3"
    Behavior on tertiary { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color error: "#ffb4ab"
    Behavior on error { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color errorContainer: "#93000a"
    Behavior on errorContainer { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color _onErrorContainer: "#ffdad6"
    Behavior on _onErrorContainer { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }
    property alias onErrorContainer: root._onErrorContainer

    property color surfaceContainerLowest: "#090f0d"
    Behavior on surfaceContainerLowest { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color surfaceContainerLow: "#171d1b"
    Behavior on surfaceContainerLow { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color surfaceContainerHigh: "#252b29"
    Behavior on surfaceContainerHigh { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color surfaceContainerHighest: "#303634"
    Behavior on surfaceContainerHighest { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color _onSurface: "#dee4e0"
    Behavior on _onSurface { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }
    property alias onSurface: root._onSurface

    property color _onSurfaceVariant: "#bfc9c4"
    Behavior on _onSurfaceVariant { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }
    property alias onSurfaceVariant: root._onSurfaceVariant

    property color outline: "#89938e"
    Behavior on outline { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    property color outlineVariant: "#3f4945"
    Behavior on outlineVariant { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    // Material 3 modal scrim, used by the embedded sheets.
    property color scrim: "#000000"
    Behavior on scrim { ColorAnimation { duration: root.paletteFade; easing.type: Motion.themeEasing } }

    // Black used by the corner-only screen frame. Not a Matugen role: those
    // corners stay black in both themes, so they do not crossfade.
    readonly property color frameCorner: "#000000"

    function snakeToCamel(str) {
        return str.replace(/_([a-z])/g, function (match, letter) {
            return letter.toUpperCase();
        });
    }

    // Material 3 state layers and translucent surfaces.
    function withAlpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function stateLayer(color, opacity) {
        return withAlpha(color, opacity);
    }

    property FileView _fileView: FileView {
        path: ShellPaths.colorsJson
        watchChanges: true

        onFileChanged: {
            this.reload();
        }

        onLoaded: {
            try {
                var content = this.text();
                if (content && content.trim() !== "") {
                    var parsed = JSON.parse(content);

                    for (var jsonKey in parsed) {
                        var qmlProperty = root.snakeToCamel(jsonKey);
                        if (qmlProperty in root) {
                            root[qmlProperty] = parsed[jsonKey];
                        }
                    }

                    // Only enable the crossfade once a palette has landed; the
                    // assignments above must not animate from the defaults.
                    root.paletteReady = true;
                }
            } catch (e) {
                console.error("Colors.qml: Помилка парсингу colors.json ->", e);
            }
        }

        onLoadFailed: {
            console.error("Colors.qml: Не вдалося завантажити colors.json");
        }
    }
}
