.pragma library

// Pure helpers behind the shortcuts overlay. `hyprctl binds -j` is parsed into
// grouped, human-readable rows; no timers, processes or QML types live here.
// Callers pass the raw JSON text and the current filter in, and render the
// returned groups.
//
// Hyprland reports the key and the modifier mask but, with a Lua config, not
// the dispatcher argument (it is an internal index), so every bind should
// carry a `description` in hyprland.lua/user.lua. Without one the row falls
// back to a generic name derived from the dispatcher.

const MOD_SHIFT = 1
const MOD_CTRL = 4
const MOD_ALT = 8
const MOD_MOD2 = 16
const MOD_MOD3 = 32
const MOD_SUPER = 64
const MOD_MOD5 = 128

// Display order and names of the modifiers Hyprland reports. Caps Lock is
// intentionally absent: it is a modifier bit but never part of a bind users
// look up.
const MODIFIERS = [
    { bit: MOD_SUPER, label: "Super" },
    { bit: MOD_SHIFT, label: "Shift" },
    { bit: MOD_CTRL, label: "Ctrl" },
    { bit: MOD_ALT, label: "Alt" },
    { bit: MOD_MOD2, label: "Mod2" },
    { bit: MOD_MOD3, label: "Mod3" },
    { bit: MOD_MOD5, label: "Mod5" },
]

// Keys whose raw Hyprland name is unreadable in a cheat sheet. Left/right
// Super collapse to one label so the two lone-Super binds render as one row.
const NAMED_KEYS = {
    "mouse:272": "Left mouse",
    "mouse:273": "Right mouse",
    "mouse:274": "Middle mouse",
    "mouse_down": "Scroll down",
    "mouse_up": "Scroll up",
    "switch:on:Lid Switch": "Lid close",
    "XF86AudioRaiseVolume": "Volume up",
    "XF86AudioLowerVolume": "Volume down",
    "XF86AudioMute": "Mute output",
    "XF86AudioMicMute": "Mute mic",
    "XF86MonBrightnessUp": "Brightness up",
    "XF86MonBrightnessDown": "Brightness down",
    "XF86AudioPlay": "Play",
    "XF86AudioPause": "Pause",
    "XF86AudioNext": "Next track",
    "XF86AudioPrev": "Previous track",
    "SUPER_L": "Super",
    "SUPER_R": "Super",
}

// Fallback wording when a bind has no description.
const DISPATCHERS = {
    exec_cmd: "Run command",
    exec: "Run command",
    close: "Close window",
    kill: "Close window",
    float: "Toggle floating",
    pseudo: "Toggle pseudo tiling",
    focus: "Focus",
    move: "Move window",
    toggle_special: "Toggle scratchpad",
    drag: "Drag window",
    resize: "Resize window",
    fullscreen: "Toggle fullscreen",
    pin: "Toggle pin",
    exit: "Exit session",
    workspace: "Switch workspace",
}

// Splits "HL.Dispatcher(exec_cmd)" into "exec_cmd".
function dispatcherName(raw) {
    const text = String(raw || "")
    const open = text.indexOf("(")
    const close = text.lastIndexOf(")")

    if (open >= 0 && close > open)
        return text.substring(open + 1, close)
    return text
}

function modifierLabels(modmask) {
    const labels = []

    for (let i = 0; i < MODIFIERS.length; i++) {
        if ((modmask & MODIFIERS[i].bit) !== 0)
            labels.push(MODIFIERS[i].label)
    }
    return labels
}

function modifierRank(label) {
    for (let i = 0; i < MODIFIERS.length; i++) {
        if (MODIFIERS[i].label === label)
            return i
    }
    return MODIFIERS.length
}

function keyLabel(bind) {
    const key = String(bind.key || "")

    if (NAMED_KEYS[key] !== undefined)
        return NAMED_KEYS[key]

    if (key === "")
        return bind.keycode ? ("Code " + bind.keycode) : ""

    if (key.length === 1)
        return key.toUpperCase()

    return key
}

function describe(bind) {
    const description = String(bind.description || "").trim()

    if (description !== "")
        return description

    const name = dispatcherName(bind.dispatcher)
    return DISPATCHERS[name] || name || "Unnamed action"
}

// Sort rows by key so a section reads like a keyboard: digits (1…9, then 0),
// letters, then named keys and gestures.
function keyRank(key) {
    if (/^[0-9]$/.test(key))
        return "0" + (key === "0" ? "9" : key)
    if (/^[A-Z]$/.test(key))
        return "1" + key
    if (key.charCodeAt(0) < 128)
        return "2" + key
    return "3" + key
}

function compareKeys(a, b) {
    const ra = keyRank(a)
    const rb = keyRank(b)

    if (ra < rb)
        return -1
    if (ra > rb)
        return 1
    return 0
}

function compareGroups(a, b) {
    // Unmodified (hardware) keys are the least common lookup, so they go last.
    const aSpecial = a.modifiers.length === 0
    const bSpecial = b.modifiers.length === 0

    if (aSpecial !== bSpecial)
        return aSpecial ? 1 : -1

    if (a.modifiers.length !== b.modifiers.length)
        return a.modifiers.length - b.modifiers.length

    for (let i = 0; i < a.modifiers.length; i++) {
        const rank = modifierRank(a.modifiers[i]) - modifierRank(b.modifiers[i])

        if (rank !== 0)
            return rank
    }

    if (a.title < b.title)
        return -1
    if (a.title > b.title)
        return 1
    return 0
}

// parse(jsonText, filter) -> { groups, total, error }
// groups: [{ title, modifiers, shortcuts: [{ key, description, group }] }]
// total counts the rows left after filtering; error is a user-facing string
// when the JSON could not be read.
function parse(jsonText, queryText) {
    let binds = []

    try {
        binds = JSON.parse(jsonText || "[]")
    } catch (e) {
        return { groups: [], total: 0, error: "Could not read the Hyprland bind list" }
    }

    if (!Array.isArray(binds))
        return { groups: [], total: 0, error: "Could not read the Hyprland bind list" }

    const query = String(queryText || "").trim().toLowerCase()
    const buckets = {}
    const order = []
    let total = 0

    for (let i = 0; i < binds.length; i++) {
        const bind = binds[i] || {}

        if (bind.catch_all === true)
            continue

        const modifiers = modifierLabels(bind.modmask || 0)
        const key = keyLabel(bind)

        if (key === "")
            continue

        const description = describe(bind)
        const submap = String(bind.submap || "")
        const title = submap !== ""
            ? ("Submap: " + submap)
            : (modifiers.length === 0 ? "Hardware keys" : modifiers.join(" + "))

        if (query !== "") {
            const haystack = (key + " " + description + " " + title).toLowerCase()

            if (haystack.indexOf(query) < 0)
                continue
        }

        if (buckets[title] === undefined) {
            buckets[title] = {
                title: title,
                modifiers: modifiers,
                shortcuts: [],
                seen: {},
            }
            order.push(title)
        }

        const bucket = buckets[title]
        const identity = key + "\u0000" + description

        if (bucket.seen[identity] === true)
            continue

        bucket.seen[identity] = true
        bucket.shortcuts.push({
            key: key,
            description: description,
            group: title,
        })
        total++
    }

    const groups = []

    for (let i = 0; i < order.length; i++) {
        const bucket = buckets[order[i]]

        bucket.shortcuts.sort(function (a, b) {
            return compareKeys(a.key, b.key)
        })
        delete bucket.seen
        groups.push(bucket)
    }

    groups.sort(compareGroups)

    return { groups: groups, total: total, error: "" }
}
