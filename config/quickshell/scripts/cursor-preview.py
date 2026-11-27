#!/usr/bin/env python3
"""Render installed Xcursor pointers as PNG previews for the Appearance page.

The cursor row shows the two cursors the theme switch pairs (light and dark),
so the row says exactly which images it changes. Xcursor themes ship binary
`left_ptr`/`default` files, so the helper parses the format itself (no extra
dependency), crops each image to the pointer's ink so it fills the tile, and
keeps the hotspot in the report.

Single mode prints one pointer (the live theme):

    {"ok":true,"theme":"Mocu-Black-Left","cursor":"left_ptr",
     "path":"/…/cursor-previews/….png","width":41,"height":59,
     "hotspot":[63,3],"nominal":72,"luma":106}

Pair mode (`--pair --pair-script apply-cursor.sh`) asks the shell helper for
the light and dark variants, so the pairing rules stay in lib/theme.sh, and
prints both plus whether the theme actually has a pair:

    {"ok":true,"paired":true,"live":"Mocu-Black-Left",
     "light":{"ok":true,…},"dark":{"ok":true,…}}

Failures print {"ok":false,"error":"…"} and exit 1, so the row can fall back
to the pointer glyph.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path

XCURSOR_IMAGE = 0xFFFD0002
CURSOR_NAMES = ("left_ptr", "default", "arrow", "top_left_arrow")
FALLBACK_THEMES = ("default", "Adwaita")


def theme_roots() -> list[Path]:
    home = Path.home()
    roots = [home / ".icons", home / ".local/share/icons"]
    data_home = os.environ.get("XDG_DATA_HOME", "")
    if data_home:
        roots.append(Path(data_home) / "icons")
    for part in os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share"
    ).split(":"):
        if part:
            roots.append(Path(part) / "icons")
    return roots


def detect_theme() -> str:
    """The live cursor theme: gsettings, then the session env, then the
    variant lib/theme.sh applied last."""
    try:
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        name = out.stdout.strip().strip("'\"")
        if out.returncode == 0 and name:
            return name
    except (OSError, subprocess.SubprocessError):
        pass
    for var in ("KOLIR_CURSOR_THEME", "XCURSOR_THEME"):
        value = os.environ.get(var, "").strip()
        if value:
            return value
    try:
        cached = Path.home() / ".cache/kolir/cursor-theme"
        name = cached.read_text(encoding="utf-8").strip()
        if name:
            return name
    except OSError:
        pass
    return ""


def variant(script: str, mode: str) -> str:
    """The theme apply-cursor.sh would pick for a light/dark mode, or "" when
    the installed family has no such variant."""
    try:
        out = subprocess.run(
            ["sh", script, "--print", mode],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def find_cursor(theme: str) -> tuple[str, Path]:
    """First existing pointer file for the theme, then for a fallback theme."""
    names = [theme] if theme else []
    names += [t for t in FALLBACK_THEMES if t not in names]
    roots = theme_roots()
    for name in names:
        for root in roots:
            cursors = root / name / "cursors"
            for cursor in CURSOR_NAMES:
                path = cursors / cursor
                if path.is_file():
                    return cursor, path.resolve()
    raise FileNotFoundError(f"no cursor theme found for '{theme or 'default'}'")


def read_images(data: bytes) -> list[tuple[int, int, int, int, int, int, int]]:
    magic, header, _version, ntoc = struct.unpack_from("<4sIII", data, 0)
    if magic != b"Xcur":
        raise ValueError("not an Xcursor file")
    images = []
    for index in range(ntoc):
        ctype, _subtype, position = struct.unpack_from(
            "<III", data, header + index * 12
        )
        if ctype != XCURSOR_IMAGE or position + 36 > len(data):
            continue
        (
            chunk_header,
            _ctype,
            nominal,
            _cversion,
            width,
            height,
            hot_x,
            hot_y,
            _delay,
        ) = struct.unpack_from("<IIIIIIIII", data, position)
        offset = position + chunk_header
        length = width * height * 4
        if width <= 0 or height <= 0 or offset + length > len(data):
            continue
        images.append((nominal, width, height, hot_x, hot_y, offset, length))
    if not images:
        raise ValueError("no image chunks")
    return images


def pick_image(images, size: int):
    ordered = sorted(images, key=lambda image: image[0])
    for image in ordered:
        if image[0] >= size:
            return image
    return ordered[-1]


def to_rgba(data: bytes, offset: int, length: int) -> tuple[bytearray, int]:
    """Xcursor pixels are little-endian ARGB, premultiplied; PNG wants
    straight RGBA. Also returns the alpha-weighted mean luminance."""
    rgba = bytearray(length)
    luma_sum = 0
    luma_weight = 0
    for index in range(0, length, 4):
        value = (
            data[offset + index]
            | data[offset + index + 1] << 8
            | data[offset + index + 2] << 16
            | data[offset + index + 3] << 24
        )
        alpha = (value >> 24) & 0xFF
        red = (value >> 16) & 0xFF
        green = (value >> 8) & 0xFF
        blue = value & 0xFF
        if 0 < alpha < 0xFF:
            red = min(255, red * 255 // alpha)
            green = min(255, green * 255 // alpha)
            blue = min(255, blue * 255 // alpha)
        rgba[index] = red
        rgba[index + 1] = green
        rgba[index + 2] = blue
        rgba[index + 3] = alpha
        if alpha:
            luma_sum += alpha * (red * 299 + green * 587 + blue * 114) // 1000
            luma_weight += alpha
    luma = luma_sum // luma_weight if luma_weight else 0
    return rgba, luma


def crop_box(rgba: bytearray, width: int, height: int, pad: int = 1):
    """Ink bounding box plus a small padding, so the arrow fills the preview
    instead of floating in the transparent margin Xcursor stores around it."""
    left, top, right, bottom = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if rgba[row + x * 4 + 3]:
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
    if right < 0:
        return 0, 0, width, height
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(width - 1, right + pad)
    bottom = min(height - 1, bottom + pad)
    return left, top, right - left + 1, bottom - top + 1


def slice_rgba(rgba: bytearray, width: int, left: int, top: int, w: int, h: int):
    out = bytearray(w * h * 4)
    for y in range(h):
        src = ((top + y) * width + left) * 4
        out[y * w * 4 : (y + 1) * w * 4] = rgba[src : src + w * 4]
    return out


def write_png(path: Path, width: int, height: int, rgba: bytearray) -> None:
    stride = width * 4
    raw = b"".join(
        b"\x00" + bytes(rgba[row * stride : (row + 1) * stride])
        for row in range(height)
    )

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def render(theme: str, size: int, cache: Path) -> dict:
    cursor, path = find_cursor(theme)
    data = path.read_bytes()
    nominal, width, height, hot_x, hot_y, offset, length = pick_image(
        read_images(data), size
    )
    rgba, luma = to_rgba(data, offset, length)
    left, top, crop_w, crop_h = crop_box(rgba, width, height)
    rgba = slice_rgba(rgba, width, left, top, crop_w, crop_h)

    cache.mkdir(parents=True, exist_ok=True)
    stamp = path.stat().st_mtime_ns
    key = hashlib.sha1(
        f"{path}|{stamp}|{nominal}|{size}|crop".encode("utf-8")
    ).hexdigest()[:16]
    out = cache / f"{key}.png"
    if not out.is_file():
        write_png(out, crop_w, crop_h, rgba)

    return {
        "ok": True,
        "theme": path.parts[-3] if len(path.parts) > 3 else theme,
        "cursor": cursor,
        "path": str(out),
        "width": crop_w,
        "height": crop_h,
        "hotspot": [hot_x, hot_y],
        "nominal": nominal,
        "luma": luma,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", default="", help="cursor theme name")
    parser.add_argument("--size", type=int, default=64, help="preferred size")
    parser.add_argument(
        "--pair",
        action="store_true",
        help="render the light and dark variants of the installed family",
    )
    parser.add_argument(
        "--pair-script",
        default="",
        help="apply-cursor.sh, asked which theme each mode would use",
    )
    parser.add_argument(
        "--dir",
        default=str(Path.home() / ".cache/quickshell/cursor-previews"),
        help="cache directory for the rendered PNGs",
    )
    args = parser.parse_args()

    cache = Path(args.dir).expanduser()
    try:
        if args.pair:
            if not args.pair_script or not Path(args.pair_script).is_file():
                raise ValueError("--pair needs an existing --pair-script")
            live = detect_theme()
            light = variant(args.pair_script, "light") or live
            dark = variant(args.pair_script, "dark") or live
            light_entry = render(light, args.size, cache)
            dark_entry = render(dark, args.size, cache)
            print(
                json.dumps(
                    {
                        "ok": True,
                        "paired": light_entry["theme"] != dark_entry["theme"],
                        "live": live,
                        "light": light_entry,
                        "dark": dark_entry,
                    }
                )
            )
            return 0

        print(json.dumps(render(args.theme.strip() or detect_theme(), args.size, cache)))
        return 0
    except Exception as error:  # noqa: BLE001 - one JSON answer per run
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
