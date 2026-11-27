pragma Singleton
import QtQuick
import "../services"

QtObject {
    readonly property string defaultBarFont: "Google Sans"
    readonly property string defaultLauncherFont: "Google Sans Flex"
    readonly property string iconFont: "Material Symbols Rounded"

    // Settings → Fonts stores one interface family. An untouched choice keeps
    // the two original faces; a chosen family replaces both so the bar and the
    // launcher agree (hyprlock keeps Google Sans Flex for its clock).
    readonly property string barFont: FontService.interfaceFont !== ""
        ? FontService.interfaceFont
        : defaultBarFont
    readonly property string launcherFont: FontService.interfaceFont !== ""
        ? FontService.interfaceFont
        : defaultLauncherFont

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
