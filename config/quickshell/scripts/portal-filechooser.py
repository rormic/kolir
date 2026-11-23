#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""XDG Desktop Portal FileChooser backend for kolir.

The portal frontend (xdg-desktop-portal) picks this backend through
``~/.config/xdg-desktop-portal/hyprland-portals.conf`` and activates the
D-Bus name below.  The actual dialog is the Quickshell ``filePicker`` panel:
this process only translates the portal request into one IPC call and waits
for the shell to write the choice back as JSON.

Protocol
--------
``OpenFile``/``SaveFile``/``SaveFiles`` create a request directory under
``$XDG_RUNTIME_DIR/kolir/file-picker/<id>/`` and call::

    qs -p <root>/config/quickshell ipc --any-display call filePicker open <json>

The shell writes ``<id>/result.json`` with either ``{"uris": [...]}`` or
``{"cancelled": true}``.  A GLib main loop watches that file while still
dispatching ``Request.Close()``; the D-Bus method returns as soon as the
choice arrives, the user cancels, or the timeout expires.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import uuid
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

try:
    from gi.repository import GLibUnix
except ImportError:  # older GLib bindings
    GLibUnix = None

try:
    from urllib.parse import quote
except ImportError:  # pragma: no cover - Python 2 is not supported
    from urllib import quote  # type: ignore

BUS_NAME = "org.freedesktop.impl.portal.desktop.kolir"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
FILE_CHOOSER_IFACE = "org.freedesktop.impl.portal.FileChooser"
REQUEST_IFACE = "org.freedesktop.impl.portal.Request"

REQUEST_TIMEOUT_SECONDS = 10 * 60
POLL_MS = 100


def log(message: str) -> None:
    print(f"kolir-portal: {message}", file=sys.stderr, flush=True)


def resolve_root() -> Path:
    """Resolve the kolir checkout/package root without hardcoding HOME."""
    env = os.environ.get("KOLIR_ROOT", "").strip()
    if env:
        root = Path(env).expanduser().resolve()
        if (root / "config/quickshell/shell.qml").is_file():
            return root

    here = Path(__file__).resolve()
    # <root>/config/quickshell/scripts/portal-filechooser.py
    root = here.parents[3]
    if (root / "config/quickshell/shell.qml").is_file():
        return root
    return Path("/usr/share/kolir")


def find_qs() -> str | None:
    found = shutil.which("qs")
    if found:
        return found
    for candidate in ("/usr/bin/qs", "/usr/local/bin/qs"):
        if os.access(candidate, os.X_OK):
            return candidate
    return None


def runtime_result_root() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR", "").strip() or "/tmp"
    return Path(base) / "kolir" / "file-picker"


def as_string(value, default: str = "") -> str:
    if value is None:
        return default
    try:
        return str(value)
    except Exception:
        return default


def as_bool(value, default: bool = False) -> bool:
    if value is None:
        return default
    try:
        return bool(value)
    except Exception:
        return default


def as_bytestring(value) -> str:
    if value is None:
        return ""
    if isinstance(value, dbus.ByteArray):
        raw = bytes(value)
    elif isinstance(value, dbus.Array):
        try:
            raw = bytes(int(byte) & 0xFF for byte in value)
        except (TypeError, ValueError):
            raw = bytes(value)
    elif isinstance(value, (bytes, bytearray)):
        raw = bytes(value)
    else:
        raw = str(value).encode("utf-8", "surrogateescape")
    raw = raw.split(b"\0", 1)[0]
    return raw.decode("utf-8", "surrogateescape")


def parse_filters(value) -> list[dict]:
    filters: list[dict] = []
    if value is None:
        return filters
    for item in value:
        try:
            name = as_string(item[0])
            patterns: list[str] = []
            mimes: list[str] = []
            for kind, pattern in item[1]:
                if int(kind) == 0:
                    patterns.append(as_string(pattern))
                else:
                    mimes.append(as_string(pattern))
            filters.append({"name": name, "patterns": patterns, "mimes": mimes})
        except Exception as error:  # a malformed filter must not kill the dialog
            log(f"ignoring malformed filter: {error}")
    return filters


def parse_files(value) -> list[str]:
    files: list[str] = []
    if value is None:
        return files
    for item in value:
        name = as_bytestring(item)
        if name:
            files.append(name)
    return files


def file_uri(path: str) -> str:
    return "file://" + quote(os.path.abspath(path), safe="/")


def notification(message: str) -> None:
    """Best-effort user-visible error; only works while a daemon is running."""
    if not shutil.which("notify-send"):
        return
    try:
        subprocess.run(
            ["notify-send", "-a", "kolir", "File picker unavailable", message],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
    except Exception:
        pass


class FileChooserRequest(dbus.service.Object):
    """One portal request: the Request interface lives at the portal handle."""

    def __init__(self, bus, path: str, backend: "FileChooserBackend", spec: dict):
        super().__init__(bus, path)
        self.backend = backend
        self.spec = spec
        self.cancelled = False
        self.finished = False
        self.timeout_id = 0
        self.poll_id = 0
        self.result: dict | None = None
        self.reply = None
        self.error = None
        self._pending_response = (1, {})

    # -- org.freedesktop.impl.portal.Request -------------------------------
    @dbus.service.signal(REQUEST_IFACE, signature="")
    def Created(self):  # noqa: N802 - D-Bus name
        pass

    @dbus.service.method(REQUEST_IFACE, in_signature="", out_signature="")
    def Close(self):  # noqa: N802 - D-Bus name
        if self.finished:
            return
        self.cancelled = True
        self.backend.cancel_shell(self.spec["id"])
        self._finish(1, {})

    # -- local -------------------------------------------------------------
    def emit_created(self) -> None:
        try:
            self.Created()
        except Exception as error:
            log(f"could not emit Request.Created: {error}")

    def _stop_sources(self) -> None:
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
            self.timeout_id = 0
        if self.poll_id:
            GLib.source_remove(self.poll_id)
            self.poll_id = 0

    def _on_timeout(self) -> bool:
        self.timeout_id = 0
        if not self.finished:
            log(f"request {self.spec['id']} timed out")
            self.cancelled = True
            self.backend.cancel_shell(self.spec["id"])
            self._finish(1, {})
        return GLib.SOURCE_REMOVE

    def _read_result(self) -> bool:
        if self.finished:
            return GLib.SOURCE_REMOVE
        path = Path(self.spec["resultPath"])
        try:
            if not path.is_file() or path.stat().st_size <= 0:
                return GLib.SOURCE_CONTINUE
            with path.open("r", encoding="utf-8") as handle:
                self.result = json.load(handle)
        except (OSError, ValueError) as error:
            log(f"could not read {path}: {error}")
            return GLib.SOURCE_CONTINUE
        if self.cancelled or bool((self.result or {}).get("cancelled")):
            self._finish(1, {})
        else:
            self._finish(0, self._build_results())
        return GLib.SOURCE_REMOVE

    def _build_results(self) -> dict:
        uris: list[str] = []
        for path in (self.result or {}).get("uris", []) or []:
            path = as_string(path)
            if path:
                uris.append(file_uri(path))

        results: dict = {"uris": dbus.Array(uris, signature="s")}
        if (self.result or {}).get("writable") is not None:
            results["writable"] = dbus.Boolean(bool(self.result["writable"]))
        choices = (self.result or {}).get("choices")
        if isinstance(choices, list) and choices:
            results["choices"] = dbus.Array(
                [
                    dbus.Struct(
                        (str(pair[0]), str(pair[1])), signature="ss"
                    )
                    for pair in choices
                ],
                signature="(ss)",
            )
        return results

    def start(self, reply, error) -> None:
        """Begin the interaction; the D-Bus call is answered asynchronously."""
        self.reply = reply
        self.error = error
        self.emit_created()

        if not self.backend.open_shell(self.spec):
            notification("Start the kolir shell to choose files.")
            self._finish(1, {})
            return

        self.timeout_id = GLib.timeout_add_seconds(
            REQUEST_TIMEOUT_SECONDS, self._on_timeout
        )
        self.poll_id = GLib.timeout_add(POLL_MS, self._read_result)

    def _finish(self, response: int, results: dict) -> None:
        if self.finished:
            return
        self.finished = True
        self._stop_sources()
        self._pending_response = (response, results)
        # Never answer the pending OpenFile directly from inside Close(): the
        # portal holds a lock while it calls Close and cannot process the
        # answer until Close returns.  Deferring the reply to an idle callback
        # breaks that deadlock.
        GLib.idle_add(self._send_reply)

    def _send_reply(self) -> bool:
        response, results = self._pending_response
        if self.reply is not None:
            try:
                self.reply(
                    dbus.UInt32(response),
                    dbus.Dictionary(results, signature="sv"),
                )
            except Exception as error:
                log(f"could not answer the portal request: {error}")
        self._cleanup()
        return GLib.SOURCE_REMOVE

    def _cleanup(self) -> bool:
        try:
            self.remove_from_connection()
        except Exception:
            pass
        self.backend.forget(self.spec["id"])
        directory = Path(self.spec["resultPath"]).parent
        try:
            if directory.is_dir():
                for child in directory.iterdir():
                    child.unlink(missing_ok=True)
                directory.rmdir()
        except OSError:
            pass
        return GLib.SOURCE_REMOVE


class FileChooserBackend(dbus.service.Object):
    """org.freedesktop.impl.portal.FileChooser at the portal desktop path."""

    def __init__(self, bus):
        super().__init__(bus, DESKTOP_PATH)
        self.bus = bus
        self.root = resolve_root()
        self.shell_config = self.root / "config/quickshell"
        self.qs = find_qs()
        self.requests: dict[str, FileChooserRequest] = {}

    # -- IPC ---------------------------------------------------------------
    def open_shell(self, spec: dict) -> bool:
        if not self.qs or not self.shell_config.is_dir():
            log("qs or the Quickshell config is missing")
            return False
        command = [
            self.qs,
            "-p",
            str(self.shell_config),
            "ipc",
            "--any-display",
            "call",
            "filePicker",
            "open",
            json.dumps(spec, ensure_ascii=False),
        ]
        try:
            result = subprocess.run(
                command,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            log(f"qs ipc failed: {error}")
            return False
        if result.returncode != 0:
            message = (result.stderr or "").strip()
            log(f"qs ipc exited with {result.returncode}: {message}")
            return False
        return True

    def cancel_shell(self, request_id: str) -> None:
        if not self.qs or not self.shell_config.is_dir():
            return
        try:
            subprocess.Popen(
                [
                    self.qs,
                    "-p",
                    str(self.shell_config),
                    "ipc",
                    "--any-display",
                    "call",
                    "filePicker",
                    "cancel",
                    request_id,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass

    # -- request plumbing --------------------------------------------------
    def forget(self, request_id: str) -> None:
        self.requests.pop(request_id, None)

    def _new_request(self, handle: str, options, mode: str, title: str) -> FileChooserRequest:
        request_id = uuid.uuid4().hex
        directory = runtime_result_root() / request_id
        directory.mkdir(parents=True, exist_ok=True)

        filters = parse_filters(options.get("filters"))
        current_folder = as_bytestring(options.get("current_folder"))
        current_file = as_bytestring(options.get("current_file"))
        current_name = as_string(options.get("current_name"))
        if not current_name and current_file:
            current_name = os.path.basename(current_file)
        if current_file:
            current_folder = os.path.dirname(current_file) or current_folder

        if mode == "openDirectory":
            accept_default = "Select"
        elif mode in ("saveFile", "saveFiles"):
            accept_default = "Save"
        else:
            accept_default = "Open"

        spec = {
            "id": request_id,
            "mode": mode,
            "title": title or accept_default,
            "acceptLabel": as_string(options.get("accept_label"), accept_default),
            "multiple": as_bool(options.get("multiple")),
            "filters": filters,
            "currentFolder": current_folder,
            "currentName": current_name,
            "currentFile": current_file,
            "files": parse_files(options.get("files")),
            "resultPath": str(directory / "result.json"),
        }

        request = FileChooserRequest(self.bus, handle, self, spec)
        self.requests[request_id] = request
        return request

    def _dispatch(self, handle, app_id, parent_window, title, options, mode: str,
                  reply, error):
        try:
            request = self._new_request(str(handle), options, mode, as_string(title))
        except Exception as exc:
            log(f"could not create request: {exc}")
            reply(dbus.UInt32(2), dbus.Dictionary({}, signature="sv"))
            return
        try:
            request.start(reply, error)
        except Exception as exc:
            log(f"request failed: {exc}")
            request._finish(2, {})

    # -- org.freedesktop.impl.portal.FileChooser ---------------------------
    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply", "error"),
    )
    def OpenFile(self, handle, app_id, parent_window, title, options,
                 reply, error):  # noqa: N802
        directory = as_bool(options.get("directory"))
        mode = "openDirectory" if directory else "openFile"
        self._dispatch(handle, app_id, parent_window, title, options, mode,
                       reply, error)

    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply", "error"),
    )
    def SaveFile(self, handle, app_id, parent_window, title, options,
                 reply, error):  # noqa: N802
        self._dispatch(handle, app_id, parent_window, title, options, "saveFile",
                       reply, error)

    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply", "error"),
    )
    def SaveFiles(self, handle, app_id, parent_window, title, options,
                  reply, error):  # noqa: N802
        self._dispatch(handle, app_id, parent_window, title, options, "saveFiles",
                       reply, error)


def main() -> int:
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        bus_name = dbus.service.BusName(BUS_NAME, bus)
    except dbus.exceptions.NameExistsException:
        log(f"{BUS_NAME} is already running")
        return 0

    backend = FileChooserBackend(bus)
    # Keep the name and backend alive for the whole process lifetime.
    _ = (bus_name, backend)

    loop = GLib.MainLoop()

    def stop(*_args):
        loop.quit()
        return GLib.SOURCE_REMOVE

    for signum in (signal.SIGTERM, signal.SIGINT):
        if GLibUnix is not None:
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signum, stop)
        else:
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signum, stop)

    log(f"serving {BUS_NAME} from {backend.root}")
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
