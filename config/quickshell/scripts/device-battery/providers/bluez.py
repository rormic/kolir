"""Generic BlueZ battery provider.

BlueZ exposes `org.bluez.Battery1` for every device that reports a battery
through the standard Battery Service. The value is whatever the device sends:
many headsets only announce 10% steps, while some send a full percentage. It is
still the correct fallback for every brand that has no dedicated provider here.

This module also owns device discovery, because every provider consumes the
same connected-audio-device list.
"""

import dbus

from .base import Provider, Reading

BATTERY_IFACE = "org.bluez.Battery1"
DEVICE_IFACE = "org.bluez.Device1"


def _text(value):
    return "" if value is None else str(value)


def _is_audio(device):
    """True for headsets, headphones and speakers, false for mice/keyboards."""

    icon = _text(device.get("Icon"))
    if icon.startswith("audio-"):
        return True

    # Class is the 24-bit Bluetooth class of device. The major service class
    # bits are 13-23; the major device class is bits 8-12 (4 = audio/video).
    try:
        device_class = int(device.get("Class", 0))
    except (TypeError, ValueError):
        device_class = 0
    return (device_class >> 8) & 0x1F == 4


def connected_audio_devices(bus):
    """Snapshot of connected audio devices known to BlueZ.

    Returns plain dictionaries (not dbus types) so they can be cached as JSON.
    """

    manager = dbus.Interface(
        bus.get_object("org.bluez", "/"),
        "org.freedesktop.DBus.ObjectManager",
    )
    objects = manager.GetManagedObjects()

    devices = []
    for path, interfaces in objects.items():
        device = interfaces.get(DEVICE_IFACE)
        if device is None or not bool(device.get("Connected", False)):
            continue
        if not _is_audio(device):
            continue

        address = _text(device.get("Address")).upper()
        if not address:
            continue

        uuid_list = device.get("UUIDs", [])
        devices.append({
            "path": str(path),
            "address": address,
            "name": _text(
                device.get("Alias")
                or device.get("Name")
                or device.get("Address")
            ),
            "icon": _text(device.get("Icon")),
            "uuids": [str(uuid).lower() for uuid in uuid_list],
            "has_battery": BATTERY_IFACE in interfaces,
        })

    # Stable order keeps the bar chip from swapping between two devices on
    # every poll.
    devices.sort(key=lambda item: (item["name"].lower(), item["address"]))
    return devices


class BluezProvider(Provider):
    """Read the battery level BlueZ already cached for the device."""

    name = "bluez"
    exact = False

    def matches(self, device):
        return bool(device.get("has_battery"))

    def read(self, device, bus, deadline):
        try:
            properties = dbus.Interface(
                bus.get_object("org.bluez", device["path"]),
                "org.freedesktop.DBus.Properties",
            )
            value = int(properties.Get(BATTERY_IFACE, "Percentage"))
        except (dbus.DBusException, TypeError, ValueError, KeyError):
            return None

        percent = max(0, min(100, value))
        return Reading(percent=percent, charging=False, source=self.name)
