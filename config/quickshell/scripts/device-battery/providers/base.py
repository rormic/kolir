"""Provider interface for the device-battery helper.

A provider answers one question: does this connected BlueZ device expose a
battery level, and if so, what is it? Brand-specific providers live next to
this file as `providers/<brand>.py` and are registered in `providers/__init__.py`.

Providers must be cheap to skip: `matches()` runs for every connected audio
device, while `read()` is only called when the provider claims the device.
`read()` is allowed to talk to the device, so it must honour the deadline it
receives and return promptly instead of raising on a missing adapter.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Reading:
    """One battery sample for a connected device."""

    percent: int
    charging: bool
    source: str
    # True when the value came from the device's own protocol rather than the
    # coarse BlueZ cache. Exact readings are cached longer and preferred over a
    # brand-specific provider that temporarily fails.
    exact: bool = False


class Provider:
    """Base class for a battery provider."""

    # Short identifier stored in the cache and exposed in the helper output.
    name = "base"

    # True when `read()` speaks the device's own protocol.
    exact = False

    def matches(self, device):
        """Return True when this provider knows how to read `device`."""
        return False

    def read(self, device, bus, deadline):
        """Return a Reading, or None when the device did not answer."""
        return None
