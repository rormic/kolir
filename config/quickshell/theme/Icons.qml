pragma Singleton
import QtQuick

// Material Symbols names. Qt renders them as ligatures with the icon font.
QtObject {
    id: root

    readonly property string lightMode: "light_mode"
    readonly property string darkMode: "dark_mode"

    readonly property string volumeUp: "volume_up"
    readonly property string volumeDown: "volume_down"
    readonly property string volumeOff: "volume_off"
    readonly property string volumeMute: "volume_mute"

    readonly property string musicNote: "music_note"
    readonly property string record: "fiber_manual_record"
    readonly property string stop: "stop_circle"

    readonly property string brightnessLow: "brightness_4"
    readonly property string brightnessMedium: "brightness_5"
    readonly property string brightnessHigh: "brightness_6"

    readonly property string search: "search"
    readonly property string searchOff: "search_off"
    readonly property string close: "close"
    readonly property string contentPaste: "content_paste"
    readonly property string calculate: "calculate"
    readonly property string keyboardReturn: "keyboard_return"
    readonly property string chevronLeft: "chevron_left"
    readonly property string chevronRight: "chevron_right"
    readonly property string check: "check"
}
