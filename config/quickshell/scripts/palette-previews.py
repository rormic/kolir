#!/usr/bin/env python3
"""palette-previews.py — палітри всіх схем Matugen для поточної шпалери.

Використання:
    palette-previews.py --wallpaper <файл> --mode light|dark \
        --contrast <від -1 до 1> --cache <файл>

Друкує JSON:
    {"key": "...", "palettes": {"scheme-content": {"primary": "#...", ...}}}

Кожна схема генерується окремим `matugen --dry-run --json`, запуски йдуть
паралельно. Кеш ключується шляхом, mtime шпалери, режимом і контрастом, тож
повторне відкриття панелі не перераховує ті самі палітри.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

SCHEMES = [
    "scheme-content",
    "scheme-expressive",
    "scheme-fidelity",
    "scheme-fruit-salad",
    "scheme-monochrome",
    "scheme-neutral",
    "scheme-rainbow",
    "scheme-tonal-spot",
    "scheme-vibrant",
    "scheme-smart",
]

# Ролі, які показує плитка вибору схеми.
ROLES = ("primary", "secondary", "tertiary", "error", "surface_container_high")

CACHE_VERSION = 1


def palette_for(wallpaper, mode, contrast, scheme, config):
    command = [
        "matugen",
        "image",
        wallpaper,
        "--source-color-index",
        "0",
        "--mode",
        mode,
        "--type",
        scheme,
        "--contrast",
        str(contrast),
    ]
    if config:
        command += ["-c", config]
    command += ["--dry-run", "--json", "hex"]

    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError(f"{scheme}: {error}") from error

    if result.returncode != 0:
        message = result.stderr.strip() or f"exit {result.returncode}"
        raise RuntimeError(f"{scheme}: {message}")

    try:
        data = json.loads(result.stdout)
        colors = data["colors"]
    except (ValueError, KeyError, TypeError) as error:
        raise RuntimeError(f"{scheme}: invalid matugen JSON: {error}") from error

    palette = {}
    for role in ROLES:
        entry = colors.get(role)
        if not isinstance(entry, dict):
            continue

        # `default` matches the requested mode; keep dark/light as a fallback.
        value = entry.get("default") or entry.get(mode) or entry.get("dark")
        if isinstance(value, dict) and isinstance(value.get("color"), str):
            palette[role] = value["color"]

    if "primary" not in palette:
        raise RuntimeError(f"{scheme}: matugen returned no primary color")

    return palette


def cache_key(wallpaper, mode, contrast, config):
    try:
        mtime = os.stat(wallpaper).st_mtime_ns
    except OSError:
        mtime = 0

    try:
        config_mtime = os.stat(config).st_mtime_ns if config else 0
    except OSError:
        config_mtime = 0

    return "|".join(
        [str(CACHE_VERSION), os.path.realpath(wallpaper), str(mtime), mode,
         str(contrast), os.path.realpath(config) if config else "",
         str(config_mtime)]
    )


def read_cache(path, key):
    if not path:
        return None

    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None

    if not isinstance(data, dict) or data.get("key") != key:
        return None

    palettes = data.get("palettes")
    if not isinstance(palettes, dict):
        return None

    if any(scheme not in palettes for scheme in SCHEMES):
        return None

    return palettes


def write_cache(path, key, palettes):
    if not path:
        return

    directory = os.path.dirname(path) or "."
    tmp_name = ""
    try:
        os.makedirs(directory, exist_ok=True)
        handle = tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=directory, delete=False
        )
        tmp_name = handle.name
        with handle:
            json.dump({"key": key, "palettes": palettes}, handle)
        os.replace(tmp_name, path)
    except OSError as error:
        print(f"palette-previews.py: cannot write cache: {error}",
              file=sys.stderr)
        if tmp_name:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--wallpaper", required=True)
    parser.add_argument("--mode", choices=("light", "dark"), required=True)
    parser.add_argument("--contrast", default="0")
    parser.add_argument("--cache", default="")
    parser.add_argument("--config", default="")
    args = parser.parse_args()

    if not os.path.isfile(args.wallpaper) or not os.access(args.wallpaper, os.R_OK):
        print(f"palette-previews.py: unreadable wallpaper: {args.wallpaper}",
              file=sys.stderr)
        return 1

    key = cache_key(args.wallpaper, args.mode, args.contrast, args.config)
    cached = read_cache(args.cache, key)
    if cached is not None:
        json.dump({"key": key, "palettes": cached}, sys.stdout,
                  separators=(",", ":"))
        return 0

    palettes = {}
    workers = min(8, len(SCHEMES))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(palette_for, args.wallpaper, args.mode, args.contrast,
                        scheme, args.config): scheme
            for scheme in SCHEMES
        }
        for future in futures:
            scheme = futures[future]
            try:
                palettes[scheme] = future.result()
            except RuntimeError as error:
                print(f"palette-previews.py: {error}", file=sys.stderr)

    if not palettes:
        return 1

    # Keep a stable order so the cache is easy to read and diff.
    palettes = {scheme: palettes[scheme] for scheme in SCHEMES
                if scheme in palettes}

    write_cache(args.cache, key, palettes)
    json.dump({"key": key, "palettes": palettes}, sys.stdout,
              separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
