#!/usr/bin/env python3
"""Diagnose and surgically repair the caelestia shell.json.

The shell dumps its runtime config schema (property tree plus the valid bar
entry ids) into $CAELESTIA_SCHEMA (diagnose) or $CAELESTIA_FIX (repair), so
this script never hardcodes what the config looks like — it always checks
against what the running shell actually accepts.

    config-doctor.py <shell.json>            diagnose: one line per finding,
                                             "issue|<warn|fail>|<problem>|<action>",
                                             or "clean"
    config-doctor.py <shell.json> --repair   apply exactly those actions;
                                             the original is copied aside first

Repairs are strictly non-destructive: a timestamped copy of the original is
kept next to it, unknown keys close to a real one are renamed (typo), ones
with no match are dropped (the shell ignores them anyway), wrong types are
coerced when unambiguous and otherwise removed so the shell's default takes
over. A file that is not JSON at all is first re-parsed tolerantly (comments,
trailing commas); only if that fails too is it moved aside wholesale.
"""

import difflib
import json
import os
import shutil
import sys

# Schema leaves produced by the shell's walk; anything else is a subtree
LEAF_TYPES = {"boolean", "number", "string", "array", "map"}


def type_name(value):
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "null"


def coerce(value, expected):
    """Return (ok, coerced) — ok only when the conversion is unambiguous."""
    if expected == "boolean":
        if isinstance(value, (int, float)) and value in (0, 1):
            return True, bool(value)
        if isinstance(value, str) and value.strip().lower() in ("true", "false", "yes", "no", "on", "off", "1", "0"):
            return True, value.strip().lower() in ("true", "yes", "on", "1")
    elif expected == "number":
        if isinstance(value, str):
            try:
                as_num = float(value.strip())
                return True, int(as_num) if as_num.is_integer() else as_num
            except ValueError:
                pass
    elif expected == "string":
        if isinstance(value, bool):
            return True, "true" if value else "false"
        if isinstance(value, (int, float)):
            return True, str(value)
    return False, None


def tolerant_parse(text):
    """Parse JSON after stripping comments and trailing commas (string-aware)."""
    out = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            out.append(ch)
        elif ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        elif ch == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1
                continue
            out.append(ch)
        else:
            out.append(ch)
        i += 1
    return json.loads("".join(out).lstrip("﻿"))


class Doctor:
    def __init__(self, schema, bar_ids):
        self.schema = schema
        self.bar_ids = bar_ids
        self.issues = []  # {severity, problem, action, fix: callable}
        # Entries marked for removal are filtered in one pass at apply time,
        # so index-based problem reports stay valid while checking
        self._entries = []
        self._entry_drops = []

    def add(self, severity, problem, action, fix):
        self.issues.append({"severity": severity, "problem": problem, "action": action, "fix": fix})

    def check(self, cfg):
        self._walk(cfg, self.schema, "")

    def _walk(self, node, schema, path):
        for key in list(node.keys()):
            where = f"{path}.{key}" if path else key
            expected = schema.get(key)
            value = node[key]

            if expected is None:
                self._unknown_key(node, schema, key, where)
            elif isinstance(expected, dict):
                if isinstance(value, dict):
                    self._walk(value, expected, where)
                else:
                    self._bad_type(node, key, where, "object", value)
            elif expected in ("map", "array"):
                if where == "bar.entries" and isinstance(value, list):
                    self._check_entries(value)
                elif type_name(value) not in ("object", "array"):
                    self._bad_type(node, key, where, expected, value)
                # contents of maps/other arrays are user data — never touched
            elif expected in LEAF_TYPES and type_name(value) != expected:
                self._bad_type(node, key, where, expected, value)

    def _unknown_key(self, node, schema, key, where):
        taken = set(node.keys())
        candidates = [k for k in schema if k not in taken]
        match = difflib.get_close_matches(key, candidates, n=1, cutoff=0.6)
        if match:
            self.add("warn", f"{where}: unknown setting (typo?)", f"rename '{key}' to '{match[0]}'",
                     lambda n=node, k=key, m=match[0]: n.update({m: n.pop(k)}))
        else:
            self.add("warn", f"{where}: unknown setting, ignored by the shell", f"remove '{key}'",
                     lambda n=node, k=key: n.pop(k))

    def _bad_type(self, node, key, where, expected, value):
        ok, coerced = coerce(value, expected)
        if ok:
            self.add("warn", f"{where}: is {type_name(value)} {json.dumps(value)}, the shell expects {expected}",
                     f"change to {json.dumps(coerced)}",
                     lambda n=node, k=key, c=coerced: n.__setitem__(k, c))
        else:
            self.add("warn", f"{where}: is {type_name(value)}, the shell expects {expected} and falls back to its default",
                     f"remove '{key}' (the default takes over)",
                     lambda n=node, k=key: n.pop(k))

    def _check_entries(self, entries):
        drop = []
        for i, entry in enumerate(entries):
            where = f"bar.entries[{i}]"
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
                self.add("warn", f"{where}: not an {{\"id\": …}} object — the bar cannot render it",
                         "remove this entry", lambda d=drop, e=entry: d.append(id(e)))
                continue
            if entry["id"] not in self.bar_ids:
                match = difflib.get_close_matches(entry["id"], self.bar_ids, n=1, cutoff=0.6)
                if match:
                    self.add("warn", f"{where}: id \"{entry['id']}\" is not a bar module (typo?)",
                             f"rename to \"{match[0]}\"",
                             lambda e=entry, m=match[0]: e.__setitem__("id", m))
                else:
                    self.add("warn", f"{where}: id \"{entry['id']}\" is not a bar module — silently dropped. Valid: {', '.join(self.bar_ids)}",
                             "remove this entry", lambda d=drop, e=entry: d.append(id(e)))
            if "enabled" in entry and not isinstance(entry["enabled"], bool):
                ok, coerced = coerce(entry["enabled"], "boolean")
                if ok:
                    self.add("warn", f"{where}: enabled is {json.dumps(entry['enabled'])}, must be true/false",
                             f"change to {json.dumps(coerced)}",
                             lambda e=entry, c=coerced: e.__setitem__("enabled", c))
                else:
                    self.add("warn", f"{where}: enabled is {json.dumps(entry['enabled'])}, must be true/false",
                             "remove 'enabled' (entry stays visible)",
                             lambda e=entry: e.pop("enabled"))
        self._entry_drops = drop
        self._entries = entries

    def apply(self):
        for issue in self.issues:
            issue["fix"]()
        if self._entry_drops:
            self._entries[:] = [e for e in self._entries if id(e) not in self._entry_drops]


def backup_path(path, suffix):
    base = f"{path}.{suffix}"
    if not os.path.exists(base):
        return base
    n = 1
    while os.path.exists(f"{base}.{n}"):
        n += 1
    return f"{base}.{n}"


def main():
    cfg_path = sys.argv[1]
    repair = "--repair" in sys.argv[2:]

    raw = os.environ.get("CAELESTIA_SCHEMA") or os.environ.get("CAELESTIA_FIX") or ""
    payload = json.loads(raw)
    schema, bar_ids = payload["types"], payload["barIds"]

    if not os.path.exists(cfg_path):
        print("clean")
        return 0

    with open(cfg_path, encoding="utf-8") as f:
        text = f.read()

    reformat = False
    try:
        cfg = json.loads(text)
    except ValueError as strict_err:
        try:
            cfg = tolerant_parse(text)
            reformat = True
        except ValueError:
            if repair:
                aside = backup_path(cfg_path, "broken.bak")
                shutil.move(cfg_path, aside)
                print(f"not repairable as JSON ({strict_err}); moved to {os.path.basename(aside)} — the shell regenerates defaults")
                return 0
            print(f"issue|fail|not valid JSON: {strict_err}|move the file aside (a .broken.bak copy stays) and let the shell regenerate defaults")
            return 0

    if not isinstance(cfg, dict):
        if repair:
            aside = backup_path(cfg_path, "broken.bak")
            shutil.move(cfg_path, aside)
            print(f"top level is {type_name(cfg)}, not an object; moved to {os.path.basename(aside)}")
            return 0
        print(f"issue|fail|top level is {type_name(cfg)}, the shell needs an object|move the file aside and regenerate defaults")
        return 0

    # A repair can expose the next problem (a typo'd section gets renamed,
    # then its contents become checkable) — converge in passes so diagnose
    # lists the complete plan and repair leaves nothing for a second run
    found = []
    if reformat:
        found.append({"severity": "warn", "problem": "not strict JSON (comments or trailing commas)", "action": "rewrite as clean JSON"})
    for _ in range(4):
        doctor = Doctor(schema, bar_ids)
        doctor.check(cfg)
        if not doctor.issues:
            break
        found.extend(doctor.issues)
        doctor.apply()

    if not found:
        print("clean")
        return 0

    if not repair:
        for issue in found:
            print(f"issue|{issue['severity']}|{issue['problem']}|{issue['action']}")
        return 0

    kept = backup_path(cfg_path, "doctor-bak")
    shutil.copy2(cfg_path, kept)
    print(f"original kept as {os.path.basename(kept)}")
    for issue in found:
        print(f"fixed: {issue['problem']} -> {issue['action']}")
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote repaired {os.path.basename(cfg_path)} ({len(found)} fixes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
