pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

QtObject {
    id: root

    property color primary: "#86d6be"
    property color onPrimary: ("#00382c")
    property color primaryContainer: "#005141"
    property color onPrimaryContainer: ("#a2f2d9")

    property color tertiary: "#a9cbe3"

    property color error: "#ffb4ab"
    property color errorContainer: "#93000a"
    property color onErrorContainer: ("#ffdad6")

    property color surfaceContainerLowest: "#090f0d"
    property color surfaceContainerLow: "#171d1b"
    property color surfaceContainerHigh: "#252b29"
    property color surfaceContainerHighest: "#303634"
    property color onSurface: ("#dee4e0")
    property color onSurfaceVariant: ("#bfc9c4")

    property color outline: "#89938e"
    property color outlineVariant: "#3f4945"

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
