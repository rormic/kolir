.pragma library

// Pure helpers for the connected Bluetooth device list.
//
// BlueZ reports a device as an icon name (audio-headset, input-keyboard, …);
// the bar capsule and the settings row both map it to a Material Symbols
// ligature, so the mapping lives here instead of in each consumer. Nothing in
// this file touches QML state: the caller passes the `Icons` singleton in.

// Audio and input devices are what the bar capsule should lead with; a phone
// or a computer is next, and anything unknown comes last. The rank only orders
// the list, it never hides a device.
function rankOf(icon) {
    const value = String(icon || "");

    if (value.startsWith("audio-"))
        return 0;
    if (value.startsWith("input-"))
        return 1;
    if (value === "phone" || value === "phone-android" || value === "smartphone")
        return 2;
    if (value === "computer" || value === "laptop" || value === "laptop-mac")
        return 2;
    if (value === "wearable" || value === "watch")
        return 3;
    return 4;
}

function isAudio(icon) {
    return String(icon || "").startsWith("audio-");
}

// Stable order: rank first, then the display name, then the address so two
// devices with the same name never swap places between polls.
function sortDevices(devices) {
    const copy = devices.slice();

    copy.sort((left, right) => {
        const delta = rankOf(left.icon) - rankOf(right.icon);
        if (delta !== 0)
            return delta;

        const nameLeft = String(left.name || "").toLowerCase();
        const nameRight = String(right.name || "").toLowerCase();
        if (nameLeft < nameRight)
            return -1;
        if (nameLeft > nameRight)
            return 1;

        return String(left.address || "").localeCompare(String(right.address || ""));
    });

    return copy;
}

function glyph(icons, icon) {
    switch (String(icon || "")) {
        case "audio-headset":
        case "audio-headphones":
        case "headset":
            return icons.headphones;
        case "audio-input-microphone":
        case "microphone":
            return icons.mic;
        case "input-keyboard":
        case "keyboard":
            return icons.keyboard;
        case "input-mouse":
        case "mouse":
            return icons.mouse;
        case "phone":
        case "phone-android":
        case "smartphone":
            return icons.smartphone;
        case "computer":
        case "laptop":
        case "laptop-mac":
            return icons.laptop;
        case "wearable":
        case "watch":
            return icons.watch;
        case "bluetooth":
            return icons.bluetooth;
        default:
            return icons.devices;
    }
}
