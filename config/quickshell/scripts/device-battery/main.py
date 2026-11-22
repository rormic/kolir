#!/usr/bin/env python3
"""Report battery levels for connected Bluetooth audio devices as JSON.

The shell runs this once in a while and never keeps a daemon alive. Output is a
JSON array, one object per connected audio device that has a usable reading:

    [{"address": "88:92:CC:D7:FF:99", "name": "WH-CH720N",
      "percent": 12, "charging": false, "source": "sony-mdr", "exact": true}]

Readings come from the provider chain in `providers/`: brand-specific protocols
first, then the generic BlueZ battery property. Exact readings are cached for
`EXACT_TTL` seconds so a poll does not reconnect to the headset every minute;
when the provider temporarily fails, the last exact value is preferred over the
coarse BlueZ one for `STALE_TTL`.

Every failure is non-fatal: no Bluetooth adapter, no D-Bus, no python-dbus, an
unreachable headset or an unwritable cache all produce a valid empty/partial
array and exit 0, so the bar simply shows nothing. Run with `--verbose` to see
why a reading was skipped.

Requires python-dbus and python-gobject (for the D-Bus main loop). Both are
optional system packages; without them the helper prints `[]`.
"""

import argparse
import json
import os
import sys
import time
import traceback

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

CACHE_VERSION = 1
EXACT_TTL = 240       # seconds a live protocol reading stays fresh
STALE_TTL = 1800      # seconds an exact reading may survive a failed refresh
PROVIDER_TIMEOUT = 4.0  # seconds one provider may spend on one device


def _default_state_path():
    cache_home = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(cache_home, "quickshell", "device-battery.json")


def _load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            parsed = json.load(handle)
    except (OSError, ValueError):
        return {}

    if not isinstance(parsed, dict):
        return {}
    devices = parsed.get("devices")
    if not isinstance(devices, dict):
        return {}

    cache = {}
    for address, entry in devices.items():
        clean = _clean_cache_entry(entry)
        if clean is not None:
            cache[str(address).upper()] = clean
    return cache


def _clean_cache_entry(entry):
    if not isinstance(entry, dict):
        return None
    try:
        percent = int(entry.get("percent"))
        updated = float(entry.get("updated", 0))
    except (TypeError, ValueError):
        return None
    if percent < 0 or percent > 100:
        return None

    return {
        "percent": percent,
        "charging": bool(entry.get("charging", False)),
        "source": str(entry.get("source", "")),
        "exact": bool(entry.get("exact", False)),
        "updated": updated,
    }


def _save_cache(path, cache, now, previous=None):
    alive = {
        address: entry
        for address, entry in cache.items()
        if now - entry["updated"] <= STALE_TTL
    }
    if previous is not None and alive == previous:
        # Cached polls usually produce the exact same file; do not rewrite it
        # every minute just to store the same timestamps.
        return

    payload = {"version": CACHE_VERSION, "devices": alive}

    try:
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
        os.replace(temporary, path)
    except OSError:
        # The reading is still valid for this run; the next poll just has no
        # cache to fall back on.
        pass


def _fresh(entry, now, ttl):
    return entry is not None and now - entry.get("updated", 0) <= ttl


def _as_reading(entry):
    # `_updated` carries the cache timestamp through `_reading_for` so main()
    # does not reset it: refreshing it on every poll would make a cached exact
    # sample look forever fresh and the provider would never be asked again.
    return {
        "percent": entry["percent"],
        "charging": entry["charging"],
        "source": entry["source"],
        "exact": entry["exact"],
        "_updated": entry["updated"],
    }


def _try_provider(provider, device, bus, deadline, verbose):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return None

    provider_deadline = min(deadline, time.monotonic() + PROVIDER_TIMEOUT)
    try:
        reading = provider.read(device, bus, provider_deadline)
    except Exception as error:  # a provider must never break the poll
        if verbose:
            print(
                "device-battery: %s failed for %s: %s"
                % (provider.name, device["address"], error),
                file=sys.stderr,
            )
        return None
    if reading is None:
        return None

    return {
        "percent": max(0, min(100, int(reading.percent))),
        "charging": bool(reading.charging),
        "source": reading.source,
        "exact": bool(reading.exact),
        "_updated": None,
    }


def _reading_for(device, bus, providers, cached, now, deadline, verbose):
    # A recent exact value is better than reconnecting to the headset on every
    # poll, and much better than the coarse BlueZ value.
    if cached and cached["exact"] and _fresh(cached, now, EXACT_TTL):
        return _as_reading(cached)

    for provider in providers:
        if not provider.exact or not provider.matches(device):
            continue
        reading = _try_provider(provider, device, bus, deadline, verbose)
        if reading is not None:
            return reading

    # The exact provider failed (busy channel, headset asleep, another app
    # holding it). Keep the last exact sample for a while instead of dropping
    # to 10% steps.
    if cached and cached["exact"] and _fresh(cached, now, STALE_TTL):
        return _as_reading(cached)

    for provider in providers:
        if provider.exact or not provider.matches(device):
            continue
        reading = _try_provider(provider, device, bus, deadline, verbose)
        if reading is not None:
            return reading

    if cached and _fresh(cached, now, STALE_TTL):
        return _as_reading(cached)
    return None


def _build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state",
        default=_default_state_path(),
        help="cache file (default: %(default)s)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=8.0,
        help="overall time budget in seconds (default: %(default)s)",
    )
    parser.add_argument("--verbose", action="store_true")
    return parser


def main(argv=None):
    args = _build_parser().parse_args(argv)
    deadline = time.monotonic() + max(0.5, args.timeout)

    try:
        import dbus
        import dbus.mainloop.glib
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
    except Exception as error:
        if args.verbose:
            print("device-battery: D-Bus unavailable: %s" % error, file=sys.stderr)
        print("[]")
        return 0

    try:
        from providers import PROVIDERS
        from providers import bluez
    except ImportError as error:
        if args.verbose:
            print("device-battery: providers unavailable: %s" % error,
                  file=sys.stderr)
        print("[]")
        return 0

    try:
        devices = bluez.connected_audio_devices(bus)
    except Exception as error:
        if args.verbose:
            print("device-battery: BlueZ query failed: %s" % error,
                  file=sys.stderr)
        print("[]")
        return 0

    now = time.time()
    cache = _load_cache(args.state)
    previous = {address: dict(entry) for address, entry in cache.items()}
    readings = []

    for device in devices:
        address = device["address"]
        cached = cache.get(address)
        reading = None
        try:
            reading = _reading_for(
                device, bus, PROVIDERS, cached, now, deadline, args.verbose
            )
        except Exception:
            if args.verbose:
                traceback.print_exc()

        if reading is None:
            continue

        readings.append({
            "address": address,
            "name": device["name"],
            "percent": reading["percent"],
            "charging": reading["charging"],
            "source": reading["source"],
            "exact": reading["exact"],
        })

        # A reading served from the cache keeps its original timestamp, so the
        # exact TTL actually expires and the provider is asked again. A coarse
        # BlueZ reading must not erase an older exact sample: that sample is
        # what the next poll prefers if the exact provider is still busy.
        if not (cached and cached["exact"] and not reading["exact"]):
            updated = reading.get("_updated")
            if updated is None:
                updated = now
            cache[address] = {
                "percent": reading["percent"],
                "charging": reading["charging"],
                "source": reading["source"],
                "exact": reading["exact"],
                "updated": updated,
            }

    # Exact sources first (a live Sony reading explains the device better than
    # the coarse BlueZ cache), then a stable name order.
    readings.sort(key=lambda item: (
        not item["exact"], item["name"].lower(), item["address"]
    ))

    _save_cache(args.state, cache, now, previous)
    print(json.dumps(readings, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
