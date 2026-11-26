#!/usr/bin/env python3
"""Map every configured keyboard layout onto the US keys.

The launcher translates a query typed in the wrong layout instead of shipping
a hand-written table per language: "вуфвдщсл" on the Ukrainian layout spells
"deadlock" on the US one. This helper asks libxkbcommon for the layouts
Hyprland actually has and prints the pairs of level-0 characters that sit on
the same physical key but differ from the US layout:

    {"layouts": [{"name": "ua", "pairs": [["q", "й"], ...]}]}

The US layout is always the reference (group 1 of the compiled keymap), so the
configured order does not matter and a machine without "us" in its layout list
still gets a usable map. Russian is excluded on purpose (`EXCLUDED_LAYOUTS`):
it is never translated even when it is configured. SearchLogic turns the pairs into query variants.

Only the Python standard library is used; libxkbcommon is the same library the
compositor already links, so this adds no package.

Usage:
    layout-map.py                     # ask Hyprland (hyprctl getoption)
    layout-map.py --layout us,ua      # explicit list, for tests
    layout-map.py --variant ,legacy   # explicit variant list
    layout-map.py --options grp:win_space_toggle
"""

import ctypes
import ctypes.util
import json
import subprocess
import sys

US_LAYOUT = "us"

# Layouts that must never be translated, even when they are configured. Russian
# is excluded on purpose: no query typed on a Russian layout is translated, so
# it never matches anything. This lives here rather than in the QML so every
# caller of the helper gets the same behaviour.
EXCLUDED_LAYOUTS = {"ru"}


class RuleNames(ctypes.Structure):
    _fields_ = [
        ("rules", ctypes.c_char_p),
        ("model", ctypes.c_char_p),
        ("layout", ctypes.c_char_p),
        ("variant", ctypes.c_char_p),
        ("options", ctypes.c_char_p),
    ]


def load_xkbcommon():
    """Bind the handful of libxkbcommon calls the layout map needs."""
    path = ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0"
    lib = ctypes.CDLL(path)
    lib.xkb_context_new.restype = ctypes.c_void_p
    lib.xkb_context_new.argtypes = [ctypes.c_int]
    lib.xkb_context_unref.restype = None
    lib.xkb_context_unref.argtypes = [ctypes.c_void_p]
    lib.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    lib.xkb_keymap_new_from_names.argtypes = [
        ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
    lib.xkb_keymap_unref.restype = None
    lib.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
    lib.xkb_keymap_min_keycode.restype = ctypes.c_uint32
    lib.xkb_keymap_min_keycode.argtypes = [ctypes.c_void_p]
    lib.xkb_keymap_max_keycode.restype = ctypes.c_uint32
    lib.xkb_keymap_max_keycode.argtypes = [ctypes.c_void_p]
    lib.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    lib.xkb_keymap_key_get_syms_by_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
    lib.xkb_keysym_to_utf8.restype = ctypes.c_int
    lib.xkb_keysym_to_utf8.argtypes = [
        ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    return lib


def level_symbol(lib, keymap, keycode, group):
    """The single character a key produces at level 0 of `group`, or ""."""
    syms = ctypes.POINTER(ctypes.c_uint32)()
    count = lib.xkb_keymap_key_get_syms_by_level(
        keymap, keycode, group, 0, ctypes.byref(syms))
    if count != 1:
        return ""
    buf = ctypes.create_string_buffer(16)
    if lib.xkb_keysym_to_utf8(syms[0], buf, len(buf)) <= 0:
        return ""
    char = buf.value.decode("utf-8", "ignore")
    return char if len(char) == 1 else ""


def layout_pairs(lib, layout, variant, options):
    """Every key whose level-0 character differs between US and `layout`."""
    context = lib.xkb_context_new(0)
    if not context:
        return []
    names = RuleNames(
        None,
        None,
        ("%s,%s" % (US_LAYOUT, layout)).encode(),
        ("," + variant).encode(),
        options.encode() if options else None)
    keymap = lib.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
    if not keymap:
        lib.xkb_context_unref(context)
        return []
    try:
        pairs = []
        for keycode in range(lib.xkb_keymap_min_keycode(keymap),
                             lib.xkb_keymap_max_keycode(keymap) + 1):
            us = level_symbol(lib, keymap, keycode, 0)
            other = level_symbol(lib, keymap, keycode, 1)
            if us and other and us != other:
                pairs.append([us, other])
        return pairs
    finally:
        lib.xkb_keymap_unref(keymap)
        lib.xkb_context_unref(context)


def hypr_option(name):
    """The string value of a Hyprland config option, or "" when unavailable."""
    try:
        result = subprocess.run(
            ["hyprctl", "getoption", name, "-j"],
            capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    try:
        return json.loads(result.stdout).get("str") or ""
    except (ValueError, AttributeError):
        return ""


def split_list(value):
    return [item.strip() for item in (value or "").split(",")]


def base_layout(name):
    """The layout name without a `(variant)` suffix, lower-cased."""
    return name.split("(")[0].strip().lower()


def emit(payload, code=0):
    print(json.dumps(payload, ensure_ascii=False))
    return code


def main(argv):
    layout = variant = options = None

    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--layout" and args:
            layout = args.pop(0)
        elif arg == "--variant" and args:
            variant = args.pop(0)
        elif arg == "--options" and args:
            options = args.pop(0)
        else:
            return emit({"error": "unknown argument: " + arg}, 2)

    if layout is not None:
        # An explicit layout list is a test: do not consult the session.
        layouts = [item for item in split_list(layout) if item]
        variants = split_list(variant) if variant is not None else []
    else:
        layouts = [item for item in split_list(hypr_option("input:kb_layout"))
                   if item]
        variants = split_list(hypr_option("input:kb_variant"))
        if options is None:
            options = hypr_option("input:kb_options")

    try:
        lib = load_xkbcommon()
    except OSError as error:
        return emit({"error": "libxkbcommon unavailable: %s" % error}, 1)

    result = []
    for index, name in enumerate(layouts):
        base = base_layout(name)
        if base == US_LAYOUT or base in EXCLUDED_LAYOUTS:
            continue
        current = variants[index] if index < len(variants) else ""
        pairs = layout_pairs(lib, name, current, options or "")
        if pairs:
            result.append({"name": name, "pairs": pairs})
    return emit({"layouts": result})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
