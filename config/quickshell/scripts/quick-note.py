#!/usr/bin/env python3
"""Append quick tasks to the Obsidian daily note from the launcher.

The launcher runs this one-shot helper through `Process`; nothing stays
resident. Two read-only/one write subcommands:

    quick-note.py target           # where the next note would go (JSON)
    quick-note.py add "<text>"     # append "- [ ] <text>" and report (JSON)

Output is always a single JSON object. Failures print `{"ok": false, "error":
"..."}` and exit 1, so the launcher can keep its input open and show why.

The vault is resolved in this order:

    1. $KOLIR_OBSIDIAN_VAULT
    2. ~/.config/obsidian/obsidian.json (open vault, else the newest one)
    3. [templates.obsidian] output_path in the Matugen config

The daily note follows the vault's core Daily notes settings
(`.obsidian/daily-notes.json`): folder, date format and optional template.
A note that does not exist yet is created from that template, or empty when
no template is configured, exactly like Obsidian's own daily-note action.

`--vault` and `--date` exist so tests can point the helper at a throwaway
vault without touching the real one.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

OBSIDIAN_STATE = Path("~/.config/obsidian/obsidian.json")
MATUGEN_CONFIG = Path("~/.config/matugen/config.toml")
DEFAULT_FORMAT = "YYYY-MM-DD"
MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]
WEEKDAYS = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
]

# Longest tokens first so "YYYY" is not eaten by "YY".
MOMENT_TOKENS = [
    "YYYY", "MMMM", "dddd", "DDDD", "MMM", "ddd", "YY", "MM", "DD", "HH",
    "hh", "mm", "ss", "SSS", "A", "a", "Q", "W", "M", "D", "H", "h", "m", "s",
]


def fail(message):
    print(json.dumps({"ok": False, "error": message}, ensure_ascii=False))
    return 1


def find_vault(explicit=None):
    if explicit:
        vault = Path(os.path.expanduser(explicit))
        if vault.is_dir():
            return vault
        raise RuntimeError(f"Obsidian vault not found: {vault}")

    env_vault = os.environ.get("KOLIR_OBSIDIAN_VAULT", "").strip()
    if env_vault:
        vault = Path(os.path.expanduser(env_vault))
        if vault.is_dir():
            return vault

    vault = vault_from_obsidian_state()
    if vault:
        return vault

    vault = vault_from_matugen()
    if vault:
        return vault

    raise RuntimeError(
        "Obsidian vault not found: open one in Obsidian, set "
        "KOLIR_OBSIDIAN_VAULT, or run 'kolir setup --obsidian <vault>'"
    )


def vault_from_obsidian_state():
    try:
        data = json.loads(OBSIDIAN_STATE.expanduser().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None

    vaults = data.get("vaults")
    if not isinstance(vaults, dict):
        return None

    entries = [entry for entry in vaults.values() if isinstance(entry, dict)]
    entries.sort(
        key=lambda entry: (bool(entry.get("open")), entry.get("ts") or 0),
        reverse=True,
    )
    for entry in entries:
        raw = entry.get("path")
        if not isinstance(raw, str) or not raw:
            continue
        vault = Path(os.path.expanduser(raw))
        if vault.is_dir():
            return vault
    return None


def vault_from_matugen():
    try:
        import tomllib
    except ImportError:  # pragma: no cover - Python older than 3.11
        return None

    try:
        data = tomllib.loads(MATUGEN_CONFIG.expanduser().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None

    templates = data.get("templates")
    obsidian = templates.get("obsidian") if isinstance(templates, dict) else None
    output = obsidian.get("output_path") if isinstance(obsidian, dict) else None
    if not isinstance(output, str) or not output:
        return None

    target = Path(os.path.expanduser(output))
    for parent in target.parents:
        if (parent / ".obsidian").is_dir():
            return parent
    return None


def read_daily_settings(vault):
    folder = ""
    date_format = DEFAULT_FORMAT
    template = ""
    try:
        data = json.loads(
            (vault / ".obsidian" / "daily-notes.json").read_text(encoding="utf-8")
        )
    except (OSError, ValueError):
        data = None

    if isinstance(data, dict):
        if isinstance(data.get("folder"), str):
            folder = data["folder"].strip()
        if isinstance(data.get("format"), str) and data["format"].strip():
            date_format = data["format"].strip()
        if isinstance(data.get("template"), str):
            template = data["template"].strip()
    return folder, date_format, template


def format_moment(fmt, moment):
    out = []
    i = 0
    while i < len(fmt):
        if fmt[i] == "[":
            end = fmt.find("]", i + 1)
            if end != -1:
                out.append(fmt[i + 1:end])
                i = end + 1
                continue
        for token in MOMENT_TOKENS:
            if fmt.startswith(token, i):
                out.append(moment_token(token, moment))
                i += len(token)
                break
        else:
            out.append(fmt[i])
            i += 1
    return "".join(out)


def moment_token(token, moment):
    hour12 = moment.hour % 12 or 12
    values = {
        "YYYY": f"{moment.year:04d}",
        "YY": f"{moment.year % 100:02d}",
        "MMMM": MONTHS[moment.month - 1],
        "MMM": MONTHS[moment.month - 1][:3],
        "MM": f"{moment.month:02d}",
        "M": str(moment.month),
        "DDDD": f"{moment.timetuple().tm_yday:03d}",
        "DD": f"{moment.day:02d}",
        "D": str(moment.day),
        "dddd": WEEKDAYS[moment.weekday()],
        "ddd": WEEKDAYS[moment.weekday()][:3],
        "HH": f"{moment.hour:02d}",
        "H": str(moment.hour),
        "hh": f"{hour12:02d}",
        "h": str(hour12),
        "mm": f"{moment.minute:02d}",
        "m": str(moment.minute),
        "ss": f"{moment.second:02d}",
        "s": str(moment.second),
        "SSS": f"{moment.microsecond // 1000:03d}",
        "A": "AM" if moment.hour < 12 else "PM",
        "a": "am" if moment.hour < 12 else "pm",
        "Q": str((moment.month - 1) // 3 + 1),
        "W": f"{moment.isocalendar().week:02d}",
    }
    return values[token]


def daily_note_path(vault, moment):
    folder, date_format, template = read_daily_settings(vault)
    name = format_moment(date_format, moment)
    note = Path(folder) / f"{name}.md" if folder else Path(f"{name}.md")
    return vault / note, template


def render_template(template_text, moment, title):
    def replace(match):
        kind = match.group(1)
        fmt = match.group(3)
        if kind == "date":
            return format_moment(fmt or DEFAULT_FORMAT, moment)
        if kind == "time":
            return format_moment(fmt or "HH:mm", moment)
        return title

    return re.sub(r"\{\{(date|time|title)(:([^}]*))?\}\}", replace, template_text)


def relative_to_vault(vault, note):
    try:
        return str(note.relative_to(vault))
    except ValueError:
        return str(note)


def target_payload(vault, note):
    return {
        "ok": True,
        "vault": str(vault),
        "note": relative_to_vault(vault, note),
        "path": str(note),
        "exists": note.is_file(),
    }


def template_file(vault, template):
    """Resolve a template path the way Obsidian does: `.md` may be omitted."""
    base = vault / template
    for candidate in (base, base.with_name(base.name + ".md")):
        if candidate.is_file():
            return candidate
    return None


def append_note(vault, note, template, moment, text):
    created = not note.is_file()
    note.parent.mkdir(parents=True, exist_ok=True)

    content = ""
    if created and template:
        # The template path is relative to the vault root, never the note folder.
        path = template_file(vault, template)
        if path is not None:
            content = render_template(
                path.read_text(encoding="utf-8"), moment, note.stem
            )

    line = f"- [ ] {text}"
    with open(note, "a", encoding="utf-8") as handle:
        if content:
            if not content.endswith("\n"):
                content += "\n"
            handle.write(content)
        else:
            # Do not glue the bullet to content that lacks a trailing newline.
            if note.stat().st_size > 0:
                with open(note, "rb") as existing:
                    existing.seek(-1, os.SEEK_END)
                    if existing.read(1) != b"\n":
                        handle.write("\n")
        handle.write(line + "\n")
    return line, created


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("command", choices=["target", "add"])
    parser.add_argument("text", nargs="?", default="")
    parser.add_argument("--vault", default="")
    parser.add_argument("--date", default="", help="override today (YYYY-MM-DD)")
    args = parser.parse_args()

    try:
        vault = find_vault(args.vault)
        if args.date:
            moment = datetime.strptime(args.date, "%Y-%m-%d")
        else:
            moment = datetime.now()
        note, template = daily_note_path(vault, moment)

        if args.command == "target":
            print(json.dumps(target_payload(vault, note), ensure_ascii=False))
            return 0

        text = " ".join(args.text.split())
        if not text:
            return fail("Note text is empty")
        line, created = append_note(vault, note, template, moment, text)
        payload = target_payload(vault, note)
        payload.update({"ok": True, "line": line, "created": created})
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:  # keep the launcher's card readable on any failure
        return fail(str(exc))


if __name__ == "__main__":
    sys.exit(main())
