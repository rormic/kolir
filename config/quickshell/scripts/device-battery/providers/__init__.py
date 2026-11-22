"""Registered battery providers, highest priority first.

To add a brand: create `providers/<brand>.py` with a `Provider` subclass and
append an instance below. Keep exact providers before the generic BlueZ one so
a live reading wins over the coarse cached value.
"""

from . import bluez, sony

PROVIDERS = (
    sony.SonyProvider(),
    bluez.BluezProvider(),
)
