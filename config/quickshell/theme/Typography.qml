pragma Singleton
import QtQuick

QtObject {
    readonly property string barFont: "Google Sans"
    readonly property string launcherFont: "Google Sans Flex"
    readonly property string iconFont: "Material Symbols Rounded"

    // Material 3 type scale (desktop sizes).
    readonly property QtObject size: QtObject {
        readonly property int labelSmall: 11
        readonly property int labelMedium: 12
        readonly property int labelLarge: 14

        readonly property int bodyMedium: 14
        readonly property int bodyLarge: 16

        readonly property int titleSmall: 14
        readonly property int titleLarge: 22
    }

    readonly property QtObject weight: QtObject {
        readonly property int regular: Font.Normal
        readonly property int medium: Font.Medium
        readonly property int semibold: Font.DemiBold
        readonly property int bold: Font.Bold
    }
}
