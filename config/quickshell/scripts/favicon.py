#!/usr/bin/env python3
"""Print a cached favicon path for a web page.

The icon is taken from the local favicon database of Firefox-family browsers
(Zen, Firefox, LibreWolf, Waterfox), so media players that expose a page URL
through MPRIS can show the site icon without any network request.

Usage: favicon.py CACHE_DIR URL
"""

from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import sys
import time
import urllib.parse
from pathlib import Path

# Firefox-family profiles store favicons in a separate SQLite database.
# The active Zen profile can live under either ~/.config/zen or ~/.zen.
PROFILE_GLOBS = (
    ".config/zen/*/favicons.sqlite",
    ".zen/*/favicons.sqlite",
    ".mozilla/firefox/*/favicons.sqlite",
    ".config/librewolf/*/favicons.sqlite",
    ".librewolf/*/favicons.sqlite",
    ".waterfox/*/favicons.sqlite",
)

CACHE_TTL = 30 * 24 * 60 * 60

ICON_QUERY = """
    SELECT i.data
    FROM moz_pages_w_icons p
    JOIN moz_icons_to_pages ip ON ip.page_id = p.id
    JOIN moz_icons i ON i.id = ip.icon_id
    WHERE p.page_url IN ({placeholders})
      AND i.data IS NOT NULL
      AND length(i.data) > 0
    ORDER BY i.width DESC, length(i.data) DESC
    LIMIT 1
"""


def host_candidates(url: str) -> list[str]:
    """Return the host plus likely parent hosts, most specific first."""
    if "://" not in url:
        url = "https://" + url

    parsed = urllib.parse.urlsplit(url)
    host = (parsed.hostname or "").strip(".").lower()
    if not host:
        return []

    hosts = [host]
    if host.startswith("www."):
        hosts.append(host[4:])
    else:
        hosts.append("www." + host)

    # Fall back from subdomains to the parent domain: music.youtube.com
    # should still find the youtube.com icon when the subdomain has none.
    labels = host.split(".")
    for index in range(1, max(1, len(labels) - 1)):
        parent = ".".join(labels[index:])
        for candidate in (parent, "www." + parent):
            if candidate not in hosts:
                hosts.append(candidate)

    return hosts


def origins_for(url: str) -> list[str]:
    """Build the origin spellings used by Firefox in moz_pages_w_icons."""
    if "://" not in url:
        url = "https://" + url

    scheme = urllib.parse.urlsplit(url).scheme or "https"
    schemes = [scheme] + [s for s in ("https", "http") if s != scheme]

    origins: list[str] = []
    for host in host_candidates(url):
        for current in schemes:
            for suffix in ("/", ""):
                origin = f"{current}://{host}{suffix}"
                if origin not in origins:
                    origins.append(origin)
    return origins


def favicon_databases() -> list[Path]:
    databases: list[Path] = []
    home = Path.home()
    for pattern in PROFILE_GLOBS:
        for path in home.glob(pattern):
            if path.is_file() and path not in databases:
                databases.append(path)
    return databases


def read_icon(origins: list[str]) -> bytes | None:
    query = ICON_QUERY.format(placeholders=",".join("?" for _ in origins))

    for database in favicon_databases():
        try:
            # Browsers keep the database locked while running. immutable=1
            # bypasses the lock; recent writes may still sit in the -wal file,
            # but the main database holds the icons for sites visited earlier.
            uri = database.resolve().as_uri() + "?immutable=1"
            connection = sqlite3.connect(uri, uri=True, timeout=0.2)
        except sqlite3.Error as error:
            print(f"favicon: cannot open {database}: {error}", file=sys.stderr)
            continue

        try:
            row = connection.execute(query, origins).fetchone()
        except sqlite3.Error as error:
            print(f"favicon: query failed for {database}: {error}", file=sys.stderr)
            row = None
        finally:
            connection.close()

        if row and row[0]:
            return bytes(row[0])

    return None


def image_extension(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if data.startswith(b"\x00\x00\x01\x00"):
        return ".ico"
    if data.startswith(b"BM"):
        return ".bmp"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"

    head = data[:1024].lstrip().lower()
    if head.startswith(b"<svg") or (head.startswith(b"<?xml") and b"<svg" in head):
        return ".svg"

    return None


def cache_key(origin: str) -> str:
    host = urllib.parse.urlsplit(origin).hostname or origin
    safe = re.sub(r"[^a-zA-Z0-9._-]+", "_", host).strip("._")[:60] or "site"
    digest = hashlib.sha1(host.encode()).hexdigest()[:12]
    return f"{safe}-{digest}"


def cached_icon(cache_dir: Path, key: str) -> Path | None:
    for path in cache_dir.glob(f"{key}.*"):
        try:
            if path.is_file() and path.stat().st_size > 0:
                if time.time() - path.stat().st_mtime < CACHE_TTL:
                    return path
        except OSError:
            continue
    return None


def store_icon(cache_dir: Path, key: str, data: bytes) -> Path | None:
    extension = image_extension(data)
    if extension is None:
        return None

    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / f"{key}{extension}"
    temporary = cache_dir / f".{key}.tmp"

    try:
        temporary.write_bytes(data)
        os.replace(temporary, destination)
    except OSError as error:
        print(f"favicon: cannot write {destination}: {error}", file=sys.stderr)
        return None

    return destination


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: favicon.py CACHE_DIR URL", file=sys.stderr)
        return 2

    cache_dir = Path(sys.argv[1]).expanduser()
    url = sys.argv[2].strip()
    origins = origins_for(url)
    if not origins:
        return 0

    key = cache_key(origins[0])
    existing = cached_icon(cache_dir, key)
    if existing is not None:
        print(existing)
        return 0

    data = read_icon(origins)
    if data is None:
        return 0

    path = store_icon(cache_dir, key, data)
    if path is not None:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
