.pragma library

// Canonical calendar event model shared by CalendarService, the local JSON
// backend and CalendarPopup.
//
// The shape maps onto the Google Calendar Events resource and iCalendar
// VEVENT, so a future CalDAV/Google backend only translates the wire format
// instead of reworking the UI:
//
//   uid         iCalUID
//   summary     summary
//   description description
//   location    location
//   start       start.dateTime (timed, "YYYY-MM-DDTHH:mm:ss") or
//               start.date (all-day, "YYYY-MM-DD")
//   end         end.dateTime / end.date. An all-day end is exclusive, exactly
//               like Google's API and iCalendar DTEND.
//   allDay      selects which of the two start/end shapes is used
//   timeZone    start.timeZone (IANA name, e.g. "Europe/Kyiv")
//   created     epoch milliseconds (Google reports RFC 3339 instead)
//   updated     epoch milliseconds
//   calendarId  which calendar the event belongs to ("local" for now)
//
// Unknown keys (etag, recurrence, attendees, reminders, …) survive
// normalisation unchanged, so a synced backend never loses remote metadata.
//
// Everything here is pure: dates arrive as parameters, nothing reads QML
// state, and no console diagnostics are emitted. CalendarService owns the
// guards and warnings.

// ── Dates ─────────────────────────────────────────────────────────────────

function pad2(value) {
    return (value < 10 ? "0" : "") + value;
}

function dayKey(date) {
    return date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
}

function keyToDate(key) {
    const value = Number(key) || 0;
    const year = Math.floor(value / 10000);
    const month = Math.floor(value / 100) % 100;
    const day = value % 100;
    return new Date(year, month - 1, day);
}

function keyToString(key) {
    const date = keyToDate(key);
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1)
        + "-" + pad2(date.getDate());
}

// "YYYY-MM-DD" (or any string starting with it) to a yyyymmdd key, else 0.
function parseDayKey(value) {
    if (typeof value !== "string")
        return 0;

    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value.trim());
    if (!match)
        return 0;

    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31)
        return 0;

    return year * 10000 + month * 100 + day;
}

function shiftDayKey(key, days) {
    const date = keyToDate(key);
    date.setDate(date.getDate() + days);
    return dayKey(date);
}

function dayKeyOf(event) {
    if (!event)
        return 0;
    return parseDayKey(event.start);
}

// ── Clock times ───────────────────────────────────────────────────────────

function formatClock(minutes) {
    const value = Math.max(0, Math.min(24 * 60 - 1, Math.round(Number(minutes) || 0)));
    return pad2(Math.floor(value / 60)) + ":" + pad2(value % 60);
}

// "9:30", "09:30", "9.30", "930" and "9" all mean the same slot; -1 means the
// field is not a valid 24-hour time yet.
function parseTime(text) {
    const value = String(text === undefined || text === null ? "" : text).trim();
    let match = /^(\d{1,2})[:.](\d{2})$/.exec(value);
    let hours;
    let minutes;

    if (match) {
        hours = Number(match[1]);
        minutes = Number(match[2]);
    } else if ((match = /^(\d{1,2})(\d{2})$/.exec(value))) {
        hours = Number(match[1]);
        minutes = Number(match[2]);
    } else if ((match = /^(\d{1,2})$/.exec(value))) {
        hours = Number(match[1]);
        minutes = 0;
    } else {
        return -1;
    }

    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59)
        return -1;

    return hours * 60 + minutes;
}

// Minutes after midnight for a timed start/end string, -1 when it has none.
function timeMinutes(value) {
    if (typeof value !== "string")
        return -1;

    const match = /T(\d{2}):(\d{2})/.exec(value);
    if (!match)
        return -1;

    return Number(match[1]) * 60 + Number(match[2]);
}

function timeLabel(event) {
    if (!event)
        return "";

    if (event.allDay)
        return "All day";

    const start = timeMinutes(event.start);
    const end = timeMinutes(event.end);
    if (start < 0)
        return "";

    if (end < 0 || end === start)
        return formatClock(start);

    return formatClock(start) + " – " + formatClock(end);
}

// ── Collections ───────────────────────────────────────────────────────────

function compareEvents(a, b) {
    const aKey = dayKeyOf(a);
    const bKey = dayKeyOf(b);
    if (aKey !== bKey)
        return aKey - bKey;

    if (!!a.allDay !== !!b.allDay)
        return a.allDay ? -1 : 1;

    const aTime = timeMinutes(a.start);
    const bTime = timeMinutes(b.start);
    if (aTime !== bTime)
        return aTime - bTime;

    return String(a.summary).localeCompare(String(b.summary));
}

function sortEvents(events) {
    if (!Array.isArray(events))
        return [];

    return events.slice().sort(compareEvents);
}

// { "yyyymmdd": count } for the month grid's presence dots. A multi-day
// all-day event counts on every day it covers; a timed event only on its start
// day. The loop is capped at one year so a malformed remote end date cannot
// spin forever.
function dayCounts(events) {
    const counts = {};
    if (!Array.isArray(events))
        return counts;

    for (const event of events) {
        const start = dayKeyOf(event);
        if (start <= 0)
            continue;

        if (event.allDay) {
            const endKey = parseDayKey(event.end);
            const hardLimit = shiftDayKey(start, 366);
            const limit = Math.min(endKey > start ? endKey : shiftDayKey(start, 1),
                hardLimit);
            let cursor = start;
            while (cursor < limit) {
                const bucket = String(cursor);
                counts[bucket] = (counts[bucket] || 0) + 1;
                cursor = shiftDayKey(cursor, 1);
            }
        } else {
            const bucket = String(start);
            counts[bucket] = (counts[bucket] || 0) + 1;
        }
    }

    return counts;
}

function eventsOn(events, key) {
    const wanted = Number(key);
    const result = [];

    if (Array.isArray(events)) {
        for (const event of events) {
            const start = dayKeyOf(event);
            if (start === wanted) {
                result.push(event);
                continue;
            }

            // A multi-day all-day event belongs to every covered day.
            if (event.allDay) {
                const endKey = parseDayKey(event.end);
                if (endKey > start && wanted >= start && wanted < endKey)
                    result.push(event);
            }
        }
    }

    return sortEvents(result);
}

function eventsInMonth(events, year, monthIndex) {
    const result = [];
    if (!Array.isArray(events))
        return result;

    for (const event of events) {
        if (event.allDay) {
            // An all-day event covers [start, end): every visible day counts.
            let cursor = dayKeyOf(event);
            const endKey = parseDayKey(event.end);
            if (cursor <= 0)
                continue;

            const limit = endKey > cursor ? endKey : shiftDayKey(cursor, 1);
            while (cursor < limit) {
                const date = keyToDate(cursor);
                if (date.getFullYear() === year && date.getMonth() === monthIndex) {
                    result.push(event);
                    break;
                }
                cursor = shiftDayKey(cursor, 1);
            }
        } else {
            const date = keyToDate(dayKeyOf(event));
            if (date.getFullYear() === year && date.getMonth() === monthIndex)
                result.push(event);
        }
    }

    return sortEvents(result);
}

// ── Event objects ─────────────────────────────────────────────────────────

function normalizeEvent(raw) {
    if (!raw || typeof raw !== "object")
        return null;

    const uid = typeof raw.uid === "string" ? raw.uid.trim() : "";
    const summary = typeof raw.summary === "string" ? raw.summary.trim() : "";
    const startKey = parseDayKey(raw.start);
    if (uid === "" || summary === "" || startKey === 0)
        return null;

    const allDay = !!raw.allDay;
    let start = String(raw.start).trim();
    let end = typeof raw.end === "string" ? raw.end.trim() : "";

    if (allDay) {
        // Google's all-day events are date-only and their end is exclusive.
        start = start.slice(0, 10);
        let endKey = parseDayKey(end);
        if (endKey === 0 || endKey <= startKey)
            endKey = shiftDayKey(startKey, 1);
        end = keyToString(endKey);
    } else if (end === "" || parseDayKey(end) === 0) {
        end = start;
    }

    return Object.assign({}, raw, {
        uid: uid,
        summary: summary,
        description: typeof raw.description === "string" ? raw.description : "",
        location: typeof raw.location === "string" ? raw.location : "",
        allDay: allDay,
        start: start,
        end: end,
        timeZone: typeof raw.timeZone === "string" ? raw.timeZone : "",
        calendarId: typeof raw.calendarId === "string" ? raw.calendarId : "local",
        created: Number(raw.created) || 0,
        updated: Number(raw.updated) || 0,
    });
}

function normalizeList(list) {
    const result = [];
    if (!Array.isArray(list))
        return result;

    for (const raw of list) {
        const event = normalizeEvent(raw);
        if (event)
            result.push(event);
    }

    return sortEvents(result);
}

function newUid() {
    const block = () => Math.floor(Math.random() * 0x10000).toString(16).padStart(4, "0");
    return [block() + block(), block(), block(), block(), block() + block() + block()]
        .join("-") + "@kolir";
}

// fields: { summary, dayKey, allDay, startMinutes, endMinutes, timeZone,
//           description, location, calendarId }
function buildEvent(fields) {
    const input = fields || {};
    const summary = typeof input.summary === "string" ? input.summary.trim() : "";
    const key = Number(input.dayKey) || 0;
    if (summary === "" || key <= 0)
        return null;

    const allDay = !!input.allDay;
    const now = Date.now();
    const event = {
        uid: newUid(),
        summary: summary,
        description: typeof input.description === "string" ? input.description : "",
        location: typeof input.location === "string" ? input.location : "",
        allDay: allDay,
        timeZone: typeof input.timeZone === "string" ? input.timeZone : "",
        start: "",
        end: "",
        calendarId: typeof input.calendarId === "string" ? input.calendarId : "local",
        created: now,
        updated: now,
    };

    if (allDay) {
        event.start = keyToString(key);
        event.end = keyToString(shiftDayKey(key, 1));
    } else {
        let startMinutes = Number(input.startMinutes);
        let endMinutes = Number(input.endMinutes);
        if (!isFinite(startMinutes) || startMinutes < 0)
            startMinutes = 9 * 60;
        if (!isFinite(endMinutes) || endMinutes <= startMinutes)
            endMinutes = Math.min(startMinutes + 60, 24 * 60 - 1);

        event.start = keyToString(key) + "T" + formatClock(startMinutes) + ":00";
        event.end = keyToString(key) + "T" + formatClock(endMinutes) + ":00";
    }

    return event;
}

function updateEvent(existing, fields) {
    if (!existing)
        return null;

    const input = fields || {};
    const built = buildEvent({
        summary: input.summary !== undefined ? input.summary : existing.summary,
        dayKey: Number(input.dayKey) || dayKeyOf(existing),
        allDay: input.allDay !== undefined ? input.allDay : existing.allDay,
        startMinutes: input.startMinutes !== undefined
            ? input.startMinutes : timeMinutes(existing.start),
        endMinutes: input.endMinutes !== undefined
            ? input.endMinutes : timeMinutes(existing.end),
        timeZone: input.timeZone !== undefined ? input.timeZone : existing.timeZone,
        description: input.description !== undefined
            ? input.description : existing.description,
        location: input.location !== undefined ? input.location : existing.location,
        calendarId: input.calendarId !== undefined
            ? input.calendarId : existing.calendarId,
    });
    if (!built)
        return null;

    // Keep remote metadata and identity; only the editable fields change.
    return Object.assign({}, existing, built, {
        uid: existing.uid,
        created: Number(existing.created) || built.created,
        updated: Date.now(),
    });
}

// ── Persistence document ──────────────────────────────────────────────────

// Returns an array of events, or null when the document is not valid JSON.
function parseState(text) {
    if (typeof text !== "string" || text.trim() === "")
        return [];

    let parsed;
    try {
        parsed = JSON.parse(text);
    } catch (error) {
        return null;
    }

    const list = Array.isArray(parsed)
        ? parsed
        : (parsed && Array.isArray(parsed.events) ? parsed.events : []);

    return normalizeList(list);
}

function serializeState(events) {
    return JSON.stringify({
        version: 1,
        provider: "local",
        events: normalizeList(events),
    });
}
