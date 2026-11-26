#!/usr/bin/env python3
"""Read and add events on Google Calendar, as JSON, for the kolir shell.

The shell never talks to Google directly. It runs this one-shot helper:

    status      cached state (account, calendars, last sync, cached events)
    auth        OAuth 2.0 loopback flow; stores a refresh token
    sync        refetch every calendar in a rolling window; caches the events
    add         create one event (and cache the result)
    disconnect  forget the tokens and the cached events

Every command prints exactly one JSON object on stdout and exits 0 on success
or 1 on failure ({ "ok": false, "error": "…" }). Diagnostics go to stderr only
with --verbose, so a missing browser or network never corrupts the answer.

The helper is deliberately read-plus-add: it calls `events.list` and
`events.insert` and never `events.patch`, `events.update` or `events.delete`.
The shell hides those actions too, but the helper is the last line of defence.

OAuth needs an OAuth client of type "Desktop app" from Google Cloud Console.
The loopback redirect (http://127.0.0.1:<random port>) needs no registration
for that client type. The client ID and secret are pasted once in Settings →
Calendar; the refresh token is stored in the state file (0600). The shell
passes the secret through KOLIR_GOOGLE_CLIENT_SECRET instead of argv, so it
never shows up in `ps`; a reconnect may omit it entirely and reuse the stored
one.

State file (default ~/.cache/quickshell/google-calendar.json):

    {"version":1,
     "clientId":"…", "clientSecret":"…", "refreshToken":"…",
     "accessToken":"…", "accessExpiry":1730000000.0,
     "account":"me@example.com",
     "calendars":[{"id":…,"summary":…,"primary":true,"color":"#…"}],
     "events":[<canonical event>…],
     "lastSync":1730000000.0, "lastError":"", "window":{"from":…,"to":…}}

The canonical event shape is the one in services/calendar/CalendarModel.js:
start/end are Google's dateTime (RFC 3339) or date (all-day, exclusive end),
the machine time zone is kept as an IANA name, and unknown remote metadata is
not needed by the shell, so only the fields it renders are kept plus the
calendar identity for the row accent.

Only the Python standard library is used.
"""

import argparse
import base64
import calendar as calendar_module
import contextlib
import fcntl
import hashlib
import http.server
import json
import os
import re
import secrets
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python < 3.9 is not supported anyway
    ZoneInfo = None

AUTH_ENDPOINT = os.environ.get(
    "KOLIR_GOOGLE_AUTH_ENDPOINT",
    "https://accounts.google.com/o/oauth2/v2/auth")
TOKEN_ENDPOINT = os.environ.get(
    "KOLIR_GOOGLE_TOKEN_ENDPOINT",
    "https://oauth2.googleapis.com/token")
API_ROOT = os.environ.get(
    "KOLIR_GOOGLE_API_ROOT",
    "https://www.googleapis.com/calendar/v3").rstrip("/")

# Least privilege: insert/read events, plus read the calendar list so the
# shell can name and colour the source. No scope lets us delete quietly,
# and `events.delete` is never called.
SCOPES = (
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
)

STATE_VERSION = 1
DEFAULT_DAYS_BACK = 30
DEFAULT_MONTHS_AHEAD = 12
HTTP_TIMEOUT = 20
MAX_PAGES = 40


class HelperError(Exception):
    def __init__(self, message, *, status=None, reauth=False):
        super().__init__(message)
        self.status = status
        self.reauth = reauth


# ── Output ────────────────────────────────────────────────────────────────

def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def log(message):
    print(message, file=sys.stderr, flush=True)


# ── State file ────────────────────────────────────────────────────────────

def default_state_path():
    cache_home = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(cache_home, "quickshell", "google-calendar.json")


def load_state(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_state(path, state):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temporary = path + ".tmp"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(temporary, path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


@contextlib.contextmanager
def state_lock(path):
    """Serialise the short read-modify-write windows between the shell's
    status/sync/add processes. Network work happens outside the lock."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    descriptor = os.open(path + ".lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def update_state(path, **changes):
    """Apply the keys the caller owns on top of a freshly read document."""
    with state_lock(path):
        state = load_state(path)
        state.update(changes)
        state["version"] = STATE_VERSION
        save_state(path, state)
        return state


# ── HTTP ──────────────────────────────────────────────────────────────────

def request_json(method, url, *, headers=None, body=None, form=None,
                 timeout=HTTP_TIMEOUT):
    request_headers = {
        "Accept": "application/json",
        "User-Agent": "kolir-google-calendar/1 (+https://github.com/kolir)",
    }
    if headers:
        request_headers.update(headers)

    payload = None
    if form is not None:
        payload = urllib.parse.urlencode(form).encode("utf-8")
        request_headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request_headers["Content-Type"] = "application/json; charset=utf-8"

    request = urllib.request.Request(
        url, data=payload, method=method, headers=request_headers)

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", "replace")
        detail = ""
        reauth = error.code == 401
        try:
            parsed = json.loads(raw) if raw.strip() else {}
        except ValueError:
            parsed = {}

        problem = parsed.get("error")
        if isinstance(problem, dict):
            detail = str(problem.get("message") or "")
        elif isinstance(problem, str):
            if problem == "invalid_grant":
                reauth = True
            # Google's token endpoint carries the human text in
            # `error_description`, the calendar API in `error.message`.
            detail = str(parsed.get("error_description") or problem)
        if not detail:
            detail = str(parsed.get("error_description") or raw.strip() or "request failed")
        # A 403 "insufficient authentication scopes" is not a per-calendar
        # permission problem: the token itself lacks the event scope, which
        # only a new consent can fix.
        if error.code == 403 and "insufficient" in detail.lower():
            reauth = True
        suffix = " (HTTP " + str(error.code) + ")" if str(error.code) not in detail else ""
        raise HelperError(detail + suffix, status=error.code, reauth=reauth)
    except urllib.error.URLError as error:
        raise HelperError("Network error: " + str(error.reason))
    except (socket.timeout, TimeoutError):
        raise HelperError("Network timeout")
    except OSError as error:
        raise HelperError("Network error: " + str(error))

    if not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
    except ValueError:
        raise HelperError("Google returned an invalid response")
    return parsed if isinstance(parsed, dict) else {}


def api_request(method, path, token, *, params=None, body=None):
    url = API_ROOT + path
    if params:
        url += "?" + urllib.parse.urlencode(params, safe=":-")
    return request_json(
        method, url, headers={"Authorization": "Bearer " + token}, body=body)


# ── OAuth ─────────────────────────────────────────────────────────────────

def refresh_access_token(state, state_path, *, force=False):
    client_id = str(state.get("clientId") or "")
    client_secret = str(state.get("clientSecret") or "")
    refresh_token = str(state.get("refreshToken") or "")

    if not refresh_token:
        raise HelperError("Google Calendar is not connected", reauth=True)
    if not client_id or not client_secret:
        raise HelperError("The OAuth client ID or secret is missing", reauth=True)

    now = time.time()
    current = str(state.get("accessToken") or "")
    expiry = float(state.get("accessExpiry") or 0)
    if not force and current and expiry > now + 60:
        return current

    token = request_json("POST", TOKEN_ENDPOINT, form={
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    })
    access_token = str(token.get("access_token") or "")
    if not access_token:
        raise HelperError("Google did not return an access token", reauth=True)

    expires_in = int(token.get("expires_in") or 3600)
    with state_lock(state_path):
        fresh = load_state(state_path)
        fresh["accessToken"] = access_token
        fresh["accessExpiry"] = time.time() + expires_in
        fresh["version"] = STATE_VERSION
        save_state(state_path, fresh)

    return access_token


def authorized(method, path, state, state_path, *, params=None, body=None):
    """One API call, retrying once after a forced refresh on 401 (a cached
    access token can be revoked or expired earlier than its reported TTL)."""
    token = refresh_access_token(state, state_path)
    try:
        return api_request(method, path, token, params=params, body=body)
    except HelperError as error:
        if error.status != 401:
            raise
        token = refresh_access_token(state, state_path, force=True)
        return api_request(method, path, token, params=params, body=body)


class _CallbackServer(http.server.HTTPServer):
    allow_reuse_address = True


def _make_handler(owner):
    class CallbackHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlsplit(self.path)
            params = urllib.parse.parse_qs(parsed.query)

            if parsed.path not in ("", "/"):
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return

            owner["result"] = {
                "code": (params.get("code") or [""])[0],
                "error": (params.get("error") or [""])[0],
                "state": (params.get("state") or [""])[0],
            }

            body = (b"<!doctype html><meta charset=\"utf-8\">"
                    b"<title>kolir</title>"
                    b"<body style=\"font-family:sans-serif;background:#111;color:#eee;"
                    b"display:grid;place-items:center;height:100vh;margin:0\">"
                    b"<div style=\"text-align:center\"><h2>Google Calendar connected</h2>"
                    b"<p>You can close this window.</p></div></body>")

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            if owner.get("verbose"):
                log("callback: " + (args[0] if args else ""))

    return CallbackHandler


def _pkce_pair():
    verifier = secrets.token_urlsafe(64)[:96]
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
    return verifier, challenge


def _fetch_calendars(token):
    items = []
    page_token = None
    for _ in range(MAX_PAGES):
        params = {"maxResults": 250, "minAccessRole": "reader"}
        if page_token:
            params["pageToken"] = page_token
        data = api_request("GET", "/users/me/calendarList", token, params=params)
        items.extend(data.get("items") or [])
        page_token = data.get("nextPageToken")
        if not page_token:
            break

    calendars = []
    for item in items:
        if item.get("deleted"):
            continue
        calendar_id = item.get("id")
        if not calendar_id:
            continue
        calendars.append({
            "id": str(calendar_id),
            "summary": str(item.get("summaryOverride") or item.get("summary")
                           or calendar_id),
            "primary": bool(item.get("primary")),
            "color": str(item.get("backgroundColor") or ""),
            "accessRole": str(item.get("accessRole") or ""),
        })

    calendars.sort(key=lambda entry: (
        0 if entry["primary"] else 1, entry["summary"].lower()))
    return calendars


def cmd_auth(args):
    client_id = args.client_id.strip()
    client_secret = args.client_secret.strip()
    if not client_id:
        raise HelperError("The OAuth client ID is empty")
    if not client_secret:
        # The shell passes the secret in the environment so it is not in argv.
        client_secret = os.environ.get("KOLIR_GOOGLE_CLIENT_SECRET", "").strip()
    if not client_secret:
        # Reconnecting reuses the secret stored on the first connect, so the
        # settings page can offer a one-click reconnect after a revocation.
        client_secret = str(load_state(args.state).get("clientSecret") or "")
    if not client_secret:
        raise HelperError("The OAuth client secret is empty")

    verifier, challenge = _pkce_pair()
    oauth_state = secrets.token_urlsafe(24)

    owner = {"result": None, "verbose": args.verbose}
    server = _CallbackServer(("127.0.0.1", 0), _make_handler(owner))
    port = server.server_address[1]
    redirect_uri = "http://127.0.0.1:" + str(port)

    query = urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "include_granted_scopes": "true",
        "prompt": "consent",
        "state": oauth_state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    auth_url = AUTH_ENDPOINT + "?" + query

    if not args.no_browser:
        opened = False
        try:
            import webbrowser
            opened = webbrowser.open(auth_url, new=2)
        except Exception:  # pragma: no cover - headless sessions
            opened = False
        if not opened:
            log("Open this URL to continue:\n" + auth_url)
    else:
        log("Open this URL to continue:\n" + auth_url)

    timeout = max(30, int(args.timeout))
    deadline = time.time() + timeout
    try:
        while owner["result"] is None and time.time() < deadline:
            server.timeout = max(0.1, min(1.0, deadline - time.time()))
            server.handle_request()
    finally:
        server.server_close()

    result = owner["result"]
    if result is None:
        raise HelperError(
            "Timed out waiting for Google. Open the browser and try again.")
    if result["error"]:
        if result["error"] == "access_denied":
            raise HelperError("Access was denied in the Google window")
        raise HelperError("Google returned: " + result["error"])
    if result["state"] != oauth_state:
        raise HelperError("The OAuth state did not match; try again")
    code = result["code"]
    if not code:
        raise HelperError("Google did not return an authorization code")

    token = request_json("POST", TOKEN_ENDPOINT, form={
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "code_verifier": verifier,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
    })
    access_token = str(token.get("access_token") or "")
    refresh_token = str(token.get("refresh_token") or "")
    if not access_token or not refresh_token:
        raise HelperError("Google did not return a refresh token. "
                          "Remove the app's access in your Google account "
                          "and connect again.")

    # Google's consent screen lets the user untick individual permissions. A
    # token without the event scope can still list calendars, which used to
    # leave the account "connected" with zero events, so refuse it loudly and
    # keep the previous state untouched.
    granted = str(token.get("scope") or "").strip()
    missing = [scope for scope in SCOPES if scope not in granted.split()] \
        if granted else []
    if missing:
        raise HelperError(
            "Google did not grant event access. Connect again and leave both "
            "calendar permissions checked.")

    calendars = _fetch_calendars(access_token)
    primary = next((entry for entry in calendars if entry["primary"]),
                   calendars[0] if calendars else {})
    account = str(primary.get("id") or "")

    previous = load_state(args.state)
    same_account = (not previous.get("account")) or previous.get("account") == account

    state = {
        "version": STATE_VERSION,
        "clientId": client_id,
        "clientSecret": client_secret,
        "refreshToken": refresh_token,
        "accessToken": access_token,
        "accessExpiry": time.time() + int(token.get("expires_in") or 3600),
        "account": account,
        "calendars": calendars,
        "primaryCalendarId": str(primary.get("id") or "primary"),
        "scopes": granted,
        "lastSync": previous.get("lastSync", 0) if same_account else 0,
        "lastError": "",
        "window": previous.get("window", {}) if same_account else {},
        "events": previous.get("events", []) if same_account else [],
    }
    save_state(args.state, state)

    return {"ok": True, "account": account, "calendars": calendars}


# ── Sync ──────────────────────────────────────────────────────────────────

def local_zone_name():
    candidate = os.environ.get("TZ") or ""
    if candidate:
        return candidate.lstrip(":")

    try:
        target = os.path.realpath("/etc/localtime")
    except OSError:
        return ""
    marker = "/zoneinfo/"
    if marker in target:
        return target.split(marker, 1)[1]
    return ""


def local_zone():
    name = local_zone_name()
    if name and ZoneInfo is not None:
        try:
            return ZoneInfo(name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo or timezone.utc


def add_months(value, months):
    index = value.month - 1 + months
    year = value.year + index // 12
    month = index % 12 + 1
    day = min(value.day, calendar_module.monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


def sync_window(days_back, months_ahead):
    zone = local_zone()
    now = datetime.now(zone)
    start = (now - timedelta(days=max(0, days_back))).replace(
        hour=0, minute=0, second=0, microsecond=0)
    end = add_months(now, max(1, months_ahead)).replace(
        hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)
    return start, end


def epoch_ms(value):
    text = str(value or "").strip()
    if not text:
        return 0
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return 0
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def canonical_event(item, calendar):
    start = item.get("start") or {}
    end = item.get("end") or {}

    all_day = bool(start.get("date"))
    if all_day:
        start_value = str(start.get("date") or "")
        end_value = str(end.get("date") or "")
    else:
        start_value = str(start.get("dateTime") or "")
        end_value = str(end.get("dateTime") or "")
        if not start_value:
            start_value = str(start.get("date") or "")
            end_value = str(end.get("date") or "")
            all_day = bool(start_value)

    if not start_value:
        return None

    uid = str(item.get("iCalUID") or item.get("id") or "")
    if not uid:
        return None

    summary = str(item.get("summary") or "").strip() or "(No title)"

    return {
        "uid": uid,
        "summary": summary,
        "description": str(item.get("description") or ""),
        "location": str(item.get("location") or ""),
        "allDay": all_day,
        "start": start_value,
        "end": end_value or start_value,
        "timeZone": str(start.get("timeZone") or ""),
        "calendarId": str(calendar.get("id") or ""),
        "calendarSummary": str(calendar.get("summary") or ""),
        "calendarColor": str(calendar.get("color") or ""),
        "created": epoch_ms(item.get("created")),
        "updated": epoch_ms(item.get("updated")),
        "readOnly": True,
        "remoteId": str(item.get("id") or ""),
        "remoteStatus": str(item.get("status") or "confirmed"),
        "htmlLink": str(item.get("htmlLink") or ""),
    }


def fetch_events(token, calendar_id, time_min, time_max):
    items = []
    page_token = None
    for _ in range(MAX_PAGES):
        params = {
            "singleEvents": "true",
            "orderBy": "startTime",
            "showDeleted": "false",
            "maxResults": 2500,
            "timeMin": time_min,
            "timeMax": time_max,
        }
        if page_token:
            params["pageToken"] = page_token
        data = api_request(
            "GET",
            "/calendars/" + urllib.parse.quote(calendar_id, safe="") + "/events",
            token,
            params=params)
        items.extend(data.get("items") or [])
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return items


def sort_events(events):
    def key(event):
        start = str(event.get("start") or "")
        return (start, 0 if event.get("allDay") else 1,
                str(event.get("summary") or "").lower())
    return sorted(events, key=key)


def dedupe_events(events):
    seen = set()
    result = []
    for event in events:
        uid = event["uid"]
        if uid in seen:
            continue
        seen.add(uid)
        result.append(event)
    return result


def cmd_sync(args):
    state = load_state(args.state)
    if not state.get("refreshToken"):
        raise HelperError("Google Calendar is not connected", reauth=True)

    # A token granted without the event scope can still list calendars. Fail
    # with the actionable message instead of returning zero events.
    stored_scopes = str(state.get("scopes") or "").strip()
    if stored_scopes and "https://www.googleapis.com/auth/calendar.events" \
            not in stored_scopes.split():
        raise HelperError(
            "Google did not grant event access. Connect again and leave both "
            "calendar permissions checked.", reauth=True)

    token = refresh_access_token(state, args.state)
    calendars = _fetch_calendars(token)

    start, end = sync_window(args.days_back, args.months_ahead)
    time_min = start.isoformat()
    time_max = end.isoformat()

    primary_id = str(state.get("primaryCalendarId") or "")
    if not primary_id:
        primary = next((entry for entry in calendars if entry["primary"]),
                       calendars[0] if calendars else {})
        primary_id = str(primary.get("id") or "primary")

    events = []
    skipped = []
    for entry in calendars:
        calendar_id = entry["id"]
        try:
            items = fetch_events(token, calendar_id, time_min, time_max)
        except HelperError as error:
            # A revoked token or a missing event scope affects every calendar,
            # so a new consent is the only fix; a single calendar's 403/404 is
            # just skipped so one shared calendar cannot empty the whole view.
            if error.status == 401 or error.reauth:
                raise
            skipped.append({
                "id": calendar_id,
                "summary": entry["summary"],
                "error": str(error),
            })
            if args.verbose:
                log("skip " + calendar_id + ": " + str(error))
            continue

        for item in items:
            if item.get("status") == "cancelled":
                continue
            event = canonical_event(item, entry)
            if event:
                events.append(event)

    events = sort_events(dedupe_events(events))
    now = time.time()
    account = str(state.get("account") or "")

    update_state(
        args.state,
        account=account,
        calendars=calendars,
        primaryCalendarId=primary_id,
        events=events,
        lastSync=now,
        lastError="",
        window={"from": time_min, "to": time_max},
    )

    return {
        "ok": True,
        "account": account,
        "calendars": calendars,
        "events": events,
        "lastSync": now,
        "window": {"from": time_min, "to": time_max},
        "skipped": skipped,
    }


# ── Add ───────────────────────────────────────────────────────────────────

def local_offset_suffix():
    offset = datetime.now().astimezone().strftime("%z")
    if re.fullmatch(r"[+-]\d{4}", offset):
        return offset[:3] + ":" + offset[3:]
    return ""


def with_offset(value):
    if re.search(r"(Z|[+-]\d{2}:?\d{2})$", value):
        return value
    return value + local_offset_suffix()


def google_event_body(event, fallback_time_zone):
    summary = str(event.get("summary") or "").strip()
    if not summary:
        raise HelperError("The event title is empty")

    start = str(event.get("start") or "").strip()
    end = str(event.get("end") or "").strip()
    if not start:
        raise HelperError("The event start is missing")

    body = {"summary": summary}
    if event.get("description"):
        body["description"] = str(event.get("description"))
    if event.get("location"):
        body["location"] = str(event.get("location"))

    if event.get("allDay"):
        start_date = start[:10]
        end_date = end[:10]
        if not end_date or end_date <= start_date:
            parsed = datetime.strptime(start_date, "%Y-%m-%d").date()
            end_date = (parsed + timedelta(days=1)).isoformat()
        body["start"] = {"date": start_date}
        body["end"] = {"date": end_date}
        return body

    zone = str(event.get("timeZone") or fallback_time_zone or "")
    body["start"] = {"dateTime": start}
    body["end"] = {"dateTime": end or start}
    if zone:
        body["start"]["timeZone"] = zone
        body["end"]["timeZone"] = zone
    else:
        body["start"]["dateTime"] = with_offset(start)
        body["end"]["dateTime"] = with_offset(end or start)
    return body


def cmd_add(args):
    state = load_state(args.state)
    if not state.get("refreshToken"):
        raise HelperError("Google Calendar is not connected", reauth=True)

    try:
        event = json.loads(args.json)
    except ValueError:
        raise HelperError("The event payload is not valid JSON")
    if not isinstance(event, dict):
        raise HelperError("The event payload must be an object")

    calendar_id = (args.calendar or state.get("primaryCalendarId")
                   or "primary")
    body = google_event_body(event, local_zone_name())

    token = refresh_access_token(state, args.state)
    response = api_request(
        "POST",
        "/calendars/" + urllib.parse.quote(str(calendar_id), safe="") + "/events",
        token,
        params={"sendUpdates": "none"},
        body=body)

    calendars = state.get("calendars") or []
    calendar = next((entry for entry in calendars
                     if entry.get("id") == str(calendar_id)), {})
    if not calendar:
        calendar = {
            "id": str(calendar_id),
            "summary": str(calendar_id),
            "primary": True,
            "color": "",
            "accessRole": "owner",
        }

    created = canonical_event(response, calendar)
    if created is None:
        raise HelperError("Google did not return the created event")

    with state_lock(args.state):
        fresh = load_state(args.state)
        events = [item for item in (fresh.get("events") or [])
                  if item.get("uid") != created["uid"]]
        events.append(created)
        fresh["events"] = sort_events(events)
        fresh["version"] = STATE_VERSION
        save_state(args.state, fresh)

    return {"ok": True, "event": created}


# ── Status / disconnect ───────────────────────────────────────────────────

def cmd_status(args):
    state = load_state(args.state)
    calendars = state.get("calendars") or []
    events = state.get("events") or []

    return {
        "ok": True,
        "configured": bool(state.get("clientId")),
        "hasSecret": bool(state.get("clientSecret")),
        "connected": bool(state.get("refreshToken")),
        "clientId": str(state.get("clientId") or ""),
        "account": str(state.get("account") or ""),
        "calendars": calendars,
        "events": events,
        "eventCount": len(events),
        "lastSync": float(state.get("lastSync") or 0),
        "window": state.get("window") or {},
        "error": str(state.get("lastError") or ""),
    }


def cmd_disconnect(args):
    state = load_state(args.state)
    kept = {
        "version": STATE_VERSION,
        "clientId": str(state.get("clientId") or ""),
        "clientSecret": str(state.get("clientSecret") or ""),
    }
    save_state(args.state, kept)
    return {"ok": True}


# ── CLI ───────────────────────────────────────────────────────────────────

def build_parser():
    parser = argparse.ArgumentParser(
        description="Google Calendar helper for the kolir shell")
    parser.add_argument(
        "--state",
        default=os.environ.get("KOLIR_GOOGLE_CALENDAR_STATE")
        or default_state_path(),
        help="state file (default: ~/.cache/quickshell/google-calendar.json)")
    parser.add_argument(
        "--verbose", action="store_true", help="print diagnostics to stderr")

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="cached state as JSON")

    auth = subparsers.add_parser("auth", help="connect a Google account")
    auth.add_argument("--client-id", required=True, dest="client_id")
    auth.add_argument("--client-secret", default="", dest="client_secret",
                      help="empty reuses the secret stored on the first connect")
    auth.add_argument("--timeout", type=int, default=300,
                      help="seconds to wait for the browser (default 300)")
    auth.add_argument("--no-browser", action="store_true",
                      help="print the URL instead of opening a browser")

    sync = subparsers.add_parser("sync", help="refetch and cache events")
    sync.add_argument("--days-back", type=int, default=DEFAULT_DAYS_BACK,
                      dest="days_back")
    sync.add_argument("--months-ahead", type=int,
                      default=DEFAULT_MONTHS_AHEAD, dest="months_ahead")

    add = subparsers.add_parser("add", help="create one event")
    add.add_argument("--json", required=True,
                     help="canonical event JSON (see CalendarModel.js)")
    add.add_argument("--calendar", default="",
                     help="calendar id (default: the account's primary)")

    subparsers.add_parser("disconnect", help="forget tokens and cached events")

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    handlers = {
        "status": cmd_status,
        "auth": cmd_auth,
        "sync": cmd_sync,
        "add": cmd_add,
        "disconnect": cmd_disconnect,
    }

    try:
        result = handlers[args.command](args)
    except HelperError as error:
        result = {"ok": False, "error": str(error)}
        if error.reauth:
            result["reauth"] = True
        emit(result)
        return 1
    except KeyboardInterrupt:
        emit({"ok": False, "error": "Cancelled"})
        return 1
    except Exception as error:  # pragma: no cover - last-resort guard
        if args.verbose:
            import traceback
            traceback.print_exc()
        emit({"ok": False, "error": "Unexpected error: " + str(error)})
        return 1

    emit(result)
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
