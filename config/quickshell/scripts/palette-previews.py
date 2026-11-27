#!/usr/bin/env python3
"""palette-previews.py — палітри всіх схем Matugen для поточної шпалери.

Використання:
    palette-previews.py --wallpaper <файл> --mode light|dark \
        --contrast <від -1 до 1> --cache <файл>

Друкує JSON:
    {"key": "...", "palettes": {"scheme-content": {"primary": "#...", ...}}}

Джерело кольору витягується один раз (`matugen image --show-source-colors`),
а кожна схема далі рендериться з `matugen color hex <source>`. Так десять
прев'ю коштують одне декодування шпалери, а не десять: квантування
зображення і є дорогою частиною, генерація схем — сота частки секунди.

`matugen color` дає ті самі M3 `colors`, що й `matugen image` (перевірено на
всіх десяти схемах, light і dark), але його `base16` інший (Matugen будує
base16 із зображення, а не з source color) і `{{ image }}` відсутній. Для
прев'ю це нешкідливо, бо вони читають лише M3-ролі; `generate-colors.sh`
свідомо лишається на `image`, коли якийсь шаблон використовує base16 або
`{{ image }}`.

Кеш ключується шляхом, mtime шпалери, режимом, контрастом і конфігом, тож
повторне відкриття панелі не перераховує ті самі палітри.
"""

import argparse
import json
import os
import re
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

# Має збігатися з `--source-color-index`, який передає generate-colors.sh
# (той самий KOLIR_MATUGEN_SOURCE_INDEX). `--show-source-colors` віддає
# кандидатів у порядку витягу й не враховує `--prefer`, тому індекс тут
# вибирається вручну зі списку.
def _source_index():
    try:
        value = int(os.environ.get("KOLIR_MATUGEN_SOURCE_INDEX", "0"))
    except ValueError:
        return 0
    return value if 0 <= value <= 4 else 0


SOURCE_INDEX = _source_index()
SOURCE_TIMEOUT = 60
SOURCE_HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

CACHE_VERSION = 2


def source_color(wallpaper, config):
    """Один раз витягнути source color зі шпалери.

    Повертає hex або None, коли Matugen не зміг перелічити кандидатів; у
    такому разі palette_for() відкотиться на повний `matugen image`.
    `-c` потрібен, щоб `[config] fallback_color` діяв і тут.
    """
    command = ["matugen", "image", wallpaper, "--show-source-colors"]
    if config:
        command += ["-c", config]

    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=SOURCE_TIMEOUT
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(f"palette-previews.py: source color: {error}", file=sys.stderr)
        return None

    if result.returncode != 0:
        message = result.stderr.strip() or f"exit {result.returncode}"
        print(f"palette-previews.py: source color: {message}",
              file=sys.stderr)
        return None

    candidates = [
        line.strip() for line in result.stdout.splitlines()
        if SOURCE_HEX.match(line.strip())
    ]
    if not candidates:
        print("palette-previews.py: source color: no candidates",
              file=sys.stderr)
        return None

    # An unchanged wallpaper can expose fewer candidates than the requested
    # index (a grayscale image has one); Matugen errors on the same case, so
    # clamp to the last candidate instead of losing every preview.
    return candidates[min(SOURCE_INDEX, len(candidates) - 1)]


def palette_for(wallpaper, source, mode, contrast, scheme, config):
    if source:
        # M3 colors are identical to the image run for the same source; see
        # the module docstring for the base16 and `{{ image }}` difference.
        command = [
            "matugen",
            "color",
            "hex",
            source,
            "--mode",
            mode,
            "--type",
            scheme,
            "--contrast",
            str(contrast),
        ]
    else:
        command = [
            "matugen",
            "image",
            wallpaper,
            "--source-color-index",
            str(SOURCE_INDEX),
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
         str(contrast), str(SOURCE_INDEX),
         os.path.realpath(config) if config else "", str(config_mtime)]
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

    # One image decode for all ten schemes. If the extraction fails, every
    # scheme falls back to its own `matugen image` run (the old, slower path).
    source = source_color(args.wallpaper, args.config)

    palettes = {}
    workers = min(8, len(SCHEMES))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(palette_for, args.wallpaper, source, args.mode,
                        args.contrast, scheme, args.config): scheme
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
