"""Sony MDR provider: exact battery percentage over the vendor RFCOMM channel.

Newer Sony headsets (WH-CH720N, WH-1000XM5/WF-1000XM5 and later) serve the MDR
v2 protocol on the SDP UUID below; older models serve MDR v1 on another UUID.
BlueZ's `org.bluez.Battery1` value for these devices is usually rounded to 10%
steps (and can lag behind), while the MDR `22 00` request answers with the live
1% value and a charging flag.

The protocol is documented by several community projects (Gadgetbridge,
SonyBridge, omarchy-headphones); this implementation speaks only the small
subset needed for the battery request:

    0x3E | type | seq | length (u32 BE) | payload | checksum | 0x3C

`0x3E`, `0x3C` and `0x3D` inside the body are escaped as `0x3D` plus the byte
with bit 4 cleared. Every data frame is acknowledged with a `type=0x01` frame
carrying the next sequence number. The v2 handshake (`00 00` -> protocol info)
runs before the battery request; the channel reports connected slightly before
it accepts writes, hence the short settle delay.

MDR v1 models (WH-1000XM4 and older) do not use this battery opcode; they fall
back to the generic BlueZ provider here. A v1 provider can be added next to this
file without touching the rest of the module.
"""

import os
import struct
import time

from .base import Provider, Reading

UUID_V2 = "956c7b26-d49a-4ba8-b03f-b17d393cb6e2"

HDR, TRL, ESC, MASK = 0x3E, 0x3C, 0x3D, 0xEF
DATA_MDR, ACK = 0x0C, 0x01

# The RFCOMM socket reports connected a little before it can carry data.
SETTLE_MS = 400
# If the protocol-info reply never arrives, ask for the battery anyway.
PROTOCOL_FALLBACK_MS = 800

PROFILE_PATH = "/io/github/kolir/devicebattery/p%d_%d"

START_PAYLOAD = b"\x00\x00"
BATTERY_PAYLOAD = b"\x22\x00"
PROTOCOL_INFO = 0x01
BATTERY_REPLY = 0x23


def _escape(data):
    out = bytearray()
    for value in data:
        if value in (HDR, TRL, ESC):
            out += bytes((ESC, value & MASK))
        else:
            out.append(value)
    return bytes(out)


def _unescape(data):
    out = bytearray()
    index = 0
    while index < len(data):
        if data[index] == ESC:
            index += 1
            if index >= len(data):
                break
            out.append(data[index] | 0x10)
        else:
            out.append(data[index])
        index += 1
    return bytes(out)


def _encode(data_type, sequence, payload=b""):
    body = bytes((data_type, sequence)) + struct.pack(">I", len(payload)) + payload
    checksum = sum(body) & 0xFF
    return bytes((HDR,)) + _escape(body + bytes((checksum,))) + bytes((TRL,))


def _decode(frame):
    body = _unescape(frame[1:-1])
    if len(body) < 7:
        return None
    data_type, sequence = body[0], body[1]
    length = struct.unpack(">I", body[2:6])[0]
    if len(body) < 6 + length + 1:
        return None

    payload = body[6:6 + length]
    checksum = body[6 + length]
    if checksum != sum(body[:6 + length]) & 0xFF:
        return None
    return data_type, sequence, payload


class _Session:
    """One RFCOMM conversation with a Sony headset."""

    def __init__(self, fd, loop, result, deadline):
        self.fd = fd
        self.loop = loop
        self.result = result
        self.deadline = deadline
        self.buffer = bytearray()
        self.sequence = 0
        self.finished = False
        self.battery_requested = False
        self.protocol_seen = False
        self.acknowledged = False
        self.fallback_scheduled = False

        import gi
        gi.require_version("GLib", "2.0")
        from gi.repository import GLib

        GLib.io_add_watch(
            fd,
            GLib.PRIORITY_DEFAULT,
            GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
            self._on_ready,
        )
        GLib.timeout_add(SETTLE_MS, self._start)
        GLib.timeout_add(100, self._check_deadline)

    def _start(self):
        self._send(START_PAYLOAD)
        return False

    def _send(self, payload):
        if self.finished:
            return
        try:
            os.write(self.fd, _encode(DATA_MDR, self.sequence, payload))
        except OSError:
            self._finish()

    def _request_battery(self):
        if self.finished or self.battery_requested:
            return False
        self.battery_requested = True
        self._send(BATTERY_PAYLOAD)
        return False

    def _ack(self, sequence):
        try:
            # The peer's ACK carries the next sequence number it expects; an
            # incoming frame is acknowledged with the opposite number.
            os.write(self.fd, _encode(ACK, 1 - sequence))
        except OSError:
            self._finish()

    def _check_deadline(self):
        if self.finished:
            return False
        if time.monotonic() >= self.deadline:
            self._finish()
            return False
        return True

    def _on_ready(self, fd, condition):
        import gi
        from gi.repository import GLib

        if condition & (GLib.IO_HUP | GLib.IO_ERR):
            self._finish()
            return False

        try:
            data = os.read(fd, 4096)
        except OSError:
            self._finish()
            return False
        if not data:
            self._finish()
            return False

        self.buffer += data
        while not self.finished:
            start = self.buffer.find(bytes((HDR,)))
            if start < 0:
                self.buffer.clear()
                break
            end = self.buffer.find(bytes((TRL,)), start + 1)
            if end < 0:
                del self.buffer[:start]
                break

            frame = bytes(self.buffer[start:end + 1])
            del self.buffer[:end + 1]
            decoded = _decode(frame)
            if decoded is None:
                continue

            data_type, sequence, payload = decoded
            if data_type == ACK:
                self.sequence = sequence
                self.acknowledged = True
                if self.protocol_seen:
                    self._request_battery()
                elif not self.fallback_scheduled:
                    # The handshake ACK sometimes arrives before the protocol
                    # info frame; do not wait for it forever.
                    self.fallback_scheduled = True
                    GLib.timeout_add(PROTOCOL_FALLBACK_MS, self._request_battery)
                continue

            self._ack(sequence)

            if payload[:1] == bytes((PROTOCOL_INFO,)):
                self.protocol_seen = True
                if self.acknowledged:
                    self._request_battery()
            elif payload[:1] == bytes((BATTERY_REPLY,)) and len(payload) >= 4:
                self.result["percent"] = max(0, min(100, int(payload[2])))
                self.result["charging"] = bool(payload[3])
                self._finish()

        return not self.finished

    def _finish(self):
        if self.finished:
            return
        self.finished = True
        try:
            os.close(self.fd)
        except OSError:
            pass
        self.loop.quit()


def _read_battery(bus, device_path, deadline):
    import dbus
    import dbus.service
    from gi.repository import GLib

    result = {}
    loop = GLib.MainLoop()
    profile_path = PROFILE_PATH % (os.getpid(), int(time.monotonic() * 1000))

    class Profile(dbus.service.Object):
        @dbus.service.method("org.bluez.Profile1", in_signature="", out_signature="")
        def Release(self):
            pass

        @dbus.service.method(
            "org.bluez.Profile1", in_signature="oha{sv}", out_signature=""
        )
        def NewConnection(self, path, fd, properties):
            _Session(fd.take(), loop, result, deadline)

        @dbus.service.method("org.bluez.Profile1", in_signature="o", out_signature="")
        def RequestDisconnection(self, path):
            pass

    profile = Profile(bus, profile_path)
    manager = dbus.Interface(
        bus.get_object("org.bluez", "/org/bluez"),
        "org.bluez.ProfileManager1",
    )

    try:
        manager.RegisterProfile(profile_path, UUID_V2, {
            "Name": "kolir device battery",
            "Role": "client",
            "RequireAuthentication": dbus.Boolean(False),
            "RequireAuthorization": dbus.Boolean(False),
        })
    except dbus.DBusException:
        return None

    try:
        remote = dbus.Interface(
            bus.get_object("org.bluez", device_path),
            "org.bluez.Device1",
        )
        timeout = max(1, int(deadline - time.monotonic()))

        def on_error(error):
            loop.quit()

        remote.ConnectProfile(
            UUID_V2,
            reply_handler=lambda: None,
            error_handler=on_error,
            timeout=timeout,
        )
        loop.run()
    except dbus.DBusException:
        return None
    finally:
        try:
            manager.UnregisterProfile(profile_path)
        except dbus.DBusException:
            pass
        del profile

    if "percent" not in result:
        return None
    return Reading(
        percent=result["percent"],
        charging=result["charging"],
        source="sony-mdr",
        exact=True,
    )


class SonyProvider(Provider):
    name = "sony-mdr"
    exact = True

    def matches(self, device):
        return UUID_V2 in device.get("uuids", ())

    def read(self, device, bus, deadline):
        return _read_battery(bus, device["path"], deadline)
