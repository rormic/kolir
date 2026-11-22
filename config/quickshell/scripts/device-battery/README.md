# Device battery helper

`main.py` prints the battery level of connected Bluetooth audio devices as a
JSON array. `services/DeviceBatteryService.qml` runs it once a minute and
`bar/components/DeviceBattery.qml` shows the first reading. Nothing is shown
when the array is empty.

```console
$ python3 config/quickshell/scripts/device-battery/main.py --verbose
[{"address":"88:92:CC:D7:FF:99","name":"WH-CH720N","percent":12,"charging":false,"source":"sony-mdr","exact":true}]
```

The helper is deliberately one-shot: no daemon, no shell startup delay beyond
the background process, and every failure (no adapter, no D-Bus, no
`python-dbus`, headset busy) still exits 0 with a valid array.

## How a reading is chosen

1. An exact reading younger than four minutes is reused without touching the
   device.
2. Exact providers run in order (currently the Sony MDR provider).
3. If an exact provider fails, a recent exact cache entry is used instead of
   dropping to the coarse value.
4. The generic BlueZ provider (`org.bluez.Battery1`) runs last.
5. A cache entry younger than thirty minutes is the final fallback.

Connected audio devices are found through BlueZ (`org.bluez.Device1` with the
`audio-*` icon or the Audio/Video major class), so mice and keyboards never
appear. The cache lives in `~/.cache/quickshell/device-battery.json`.

## Adding a brand

Create `providers/<brand>.py`:

```python
from .base import Provider, Reading


class MyBrandProvider(Provider):
    name = "mybrand"
    exact = True              # the value is a live 1% reading
    # exact = False           # the value is coarse, but brand-specific

    def matches(self, device):
        # `device` is a plain dict from providers/bluez.py:
        # path, address, name, icon, uuids, has_battery.
        return "my-uuid-here" in device.get("uuids", ())

    def read(self, device, bus, deadline):
        # Talk to the device, or read BlueZ/D-Bus. Respect `deadline`
        # (time.monotonic()) and return None on any failure.
        return Reading(percent=87, charging=False, source=self.name, exact=True)
```

Register it in `providers/__init__.py` **before** `BluezProvider`, then check:

```console
python3 -m py_compile config/quickshell/scripts/device-battery/providers/*.py
python3 config/quickshell/scripts/device-battery/main.py --verbose
```

`read()` may import the brand's D-Bus/GLib helpers lazily. An exception is
caught per provider, so a bug in one brand must not hide the other devices; the
helper logs it only with `--verbose`.

## Sony notes

The `sony-mdr` provider uses the MDR v2 RFCOMM service
(`956c7b26-d49a-4ba8-b03f-b17d393cb6e2`), performs the `00 00` handshake and
asks `22 00`; the reply is `23 00 <percent> <charging>`. BlueZ's
`org.bluez.Battery1` value for these headsets is usually rounded to 10% steps
(and can lag behind), which is why the provider exists.

The helper needs `python-dbus` and `python-gobject` for the profile handshake
and its GLib main loop. Without them it prints `[]` and the bar stays unchanged.
Older MDR v1 headsets do not use that battery opcode; they fall back to BlueZ.
