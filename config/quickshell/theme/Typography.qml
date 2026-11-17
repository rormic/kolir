pragma Singleton
import QtQuick

QtObject {
    id: root

    // Legacy pixel surfaces keep Aseprite; the bar uses the M3 typeface.
    readonly property string mainFont: "Aseprite"
    readonly property string barFont: "Google Sans"
    readonly property string iconFont: "Material Symbols Rounded"

    // Material 3 type scale (desktop sizes).
    readonly property QtObject size: QtObject {
        readonly property int labelSmall: 11
        readonly property int labelMedium: 12
        readonly property int labelLarge: 14

        readonly property int bodySmall: 12
        readonly property int bodyMedium: 14
        readonly property int bodyLarge: 16

        readonly property int titleSmall: 14
        readonly property int titleMedium: 16
        readonly property int titleLarge: 22

        readonly property int headlineSmall: 24
        readonly property int headlineMedium: 28
    }

    readonly property QtObject weight: QtObject {
        readonly property int regular: Font.Normal
        readonly property int medium: Font.Medium
        readonly property int bold: Font.Bold
    }
}
