#!/usr/bin/env python3
"""now-playing-colors.py — палітра обкладинки для віджета Now Playing.

Використання:
    now-playing-colors.py <art-url>

Друкує JSON:
    {"primary_container": "#...", "on_primary_container": "#..."}

Локальний `file://` (або абсолютний шлях) використовується напряму; HTTP(S)
обкладинка один раз завантажується в
`${XDG_CACHE_HOME:-~/.cache}/quickshell/now-playing/<sha1-url>.<ext>` і далі
береться з кешу. Matugen запускається з `--dry-run`, тому жоден шаблон і
жоден хук не спрацьовує: змінюються тільки кольори піла.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

REQUIRED_ROLES = ("primary_container", "on_primary_container")
OPTIONAL_ROLES = ("primary", "on_primary")
ROLES = REQUIRED_ROLES + OPTIONAL_ROLES
IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif")
DOWNLOAD_TIMEOUT = 10
MATUGEN_TIMEOUT = 30


def home():
    return os.path.expanduser("~")


def cache_root():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(home(), ".cache")
    return os.path.join(base, "quickshell", "now-playing")


def local_path(url):
    """Path used directly for a file:// URL or a bare absolute path."""
    if url.startswith("file://"):
        parsed = urllib.parse.urlparse(url)
        return urllib.parse.unquote(parsed.path)
    if url.startswith("/"):
        return url
    return ""


def image_extension(url):
    path = urllib.parse.urlparse(url).path
    extension = os.path.splitext(path)[1].lower()
    return extension if extension in IMAGE_EXTENSIONS else ".img"


def download(url):
    directory = cache_root()
    target = os.path.join(
        directory, hashlib.sha1(url.encode("utf-8")).hexdigest() + image_extension(url)
    )

    if os.path.isfile(target) and os.path.getsize(target) > 0:
        return target

    os.makedirs(directory, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "kolir/1.0"})
    with urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT) as response:
        data = response.read()

    if not data:
        raise RuntimeError("empty response")

    temporary = target + ".tmp"
    with open(temporary, "wb") as handle:
        handle.write(data)
    os.replace(temporary, target)
    return target


def theme_mode():
    path = os.path.join(home(), ".cache", "current_theme")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            mode = handle.read().strip()
    except OSError:
        return "dark"
    return mode if mode in ("light", "dark") else "dark"


def palette(image, mode):
    command = [
        "matugen",
        "image",
        image,
        "--source-color-index",
        "0",
        "--mode",
        mode,
        "--dry-run",
        "--json",
        "hex",
    ]

    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=MATUGEN_TIMEOUT
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError(f"matugen: {error}") from error

    if result.returncode != 0:
        message = result.stderr.strip() or f"exit {result.returncode}"
        raise RuntimeError(f"matugen: {message}")

    try:
        colors = json.loads(result.stdout)["colors"]
    except (ValueError, KeyError, TypeError) as error:
        raise RuntimeError(f"invalid matugen JSON: {error}") from error

    values = {}
    for role in ROLES:
        entry = colors.get(role)
        if not isinstance(entry, dict):
            continue

        # `default` matches the requested mode; keep the explicit mode and
        # dark as fallbacks for older Matugen releases.
        value = entry.get("default") or entry.get(mode) or entry.get("dark")
        if isinstance(value, dict) and isinstance(value.get("color"), str):
            values[role] = value["color"]

    missing = [role for role in REQUIRED_ROLES if role not in values]
    if missing:
        raise RuntimeError(f"matugen returned no {', '.join(missing)}")

    return values


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <art-url>", file=sys.stderr)
        return 2

    url = sys.argv[1].strip()
    if not url:
        print("now-playing-colors.py: empty art URL", file=sys.stderr)
        return 1

    if shutil.which("matugen") is None:
        print("now-playing-colors.py: matugen not found", file=sys.stderr)
        return 1

    try:
        image = local_path(url)
        if image:
            if not os.path.isfile(image) or not os.access(image, os.R_OK):
                raise RuntimeError(f"unreadable cover art: {image}")
        elif url.startswith(("http://", "https://")):
            image = download(url)
        else:
            raise RuntimeError(f"unsupported art URL: {url}")

        mode = theme_mode()
        values = palette(image, mode)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"now-playing-colors.py: {error}", file=sys.stderr)
        return 1

    json.dump(values, sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
