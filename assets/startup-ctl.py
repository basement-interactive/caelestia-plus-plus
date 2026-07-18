#!/usr/bin/env python3
"""Startup-apps helper for the security center's Startup tab.

Manages XDG autostart entries (~/.config/autostart + /etc/xdg/autostart) with
the standard masking semantics: a user file shadows a system file of the same
name, and disabling a system entry writes a masked copy into the user dir.

Subcommands (all paths absolute):
    scan                         print one "as|enabled|path|name|exec|icon" line
                                 per autostart entry (user files shadow system)
    set-enabled <path> <0|1>     toggle an entry (masks system entries in ~)
    remove <path>                move a user entry to an autostart-backup dir
    add <name> <exec>            create a new user autostart entry

systemd --user units are handled directly by the shell (systemctl), not here.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

USER_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart"
SYSTEM_DIR = Path("/etc/xdg/autostart")
BACKUP_DIR = USER_DIR / "disabled-backup"


def parse(path: Path) -> dict:
    """Minimal [Desktop Entry] reader — first section only, last key wins."""
    data, in_entry = {}, False
    try:
        for raw in path.read_text(errors="replace").splitlines():
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                in_entry = line == "[Desktop Entry]"
                continue
            if in_entry and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip()
    except OSError:
        pass
    return data


def is_enabled(d: dict) -> bool:
    if d.get("Hidden", "").lower() == "true":
        return False
    if d.get("X-GNOME-Autostart-enabled", "").lower() == "false":
        return False
    return True


def set_key(path: Path, key: str, value: str) -> None:
    """Set key=value in the [Desktop Entry] section, preserving the rest."""
    lines = path.read_text(errors="replace").splitlines() if path.exists() else ["[Desktop Entry]"]
    out, in_entry, done = [], False, False
    for raw in lines:
        s = raw.strip()
        if s.startswith("[") and s.endswith("]"):
            if in_entry and not done:
                out.append(f"{key}={value}")
                done = True
            in_entry = s == "[Desktop Entry]"
        elif in_entry and "=" in s and s.split("=", 1)[0].strip() == key:
            continue  # drop the old line; we re-add below
        out.append(raw)
    if not done:
        if not any(l.strip() == "[Desktop Entry]" for l in out):
            out.insert(0, "[Desktop Entry]")
        idx = next(i for i, l in enumerate(out) if l.strip() == "[Desktop Entry]")
        out.insert(idx + 1, f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n")


def cmd_scan() -> None:
    seen = set()
    for d in (USER_DIR, SYSTEM_DIR):
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.desktop")):
            if f.name in seen or f.parent == BACKUP_DIR:
                continue
            seen.add(f.name)
            e = parse(f)
            if e.get("NoDisplay", "").lower() == "true" and not e.get("Name"):
                continue
            name = e.get("Name", f.stem).replace("|", "/")
            exe = e.get("Exec", "").replace("|", "/")
            icon = e.get("Icon", "").replace("|", "/")
            print(f"as|{1 if is_enabled(e) else 0}|{f}|{name}|{exe}|{icon}")


def cmd_set_enabled(path: str, enabled: bool) -> None:
    p = Path(path)
    if p.parent == SYSTEM_DIR:
        # System entry: mask it with a user copy, or drop the mask to re-enable.
        mask = USER_DIR / p.name
        if enabled:
            if mask.exists():
                mask.unlink()
        else:
            base = parse(p)
            USER_DIR.mkdir(parents=True, exist_ok=True)
            mask.write_text(
                f"[Desktop Entry]\nType=Application\n"
                f"Name={base.get('Name', p.stem)}\nExec={base.get('Exec', '')}\n"
                f"Icon={base.get('Icon', '')}\nHidden=true\n")
        return
    set_key(p, "Hidden", "false" if enabled else "true")
    set_key(p, "X-GNOME-Autostart-enabled", "true" if enabled else "false")


def cmd_remove(path: str) -> None:
    p = Path(path)
    if p.parent == SYSTEM_DIR:
        cmd_set_enabled(path, False)  # can't delete system files; mask instead
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    p.replace(BACKUP_DIR / p.name)


def cmd_add(name: str, exe: str) -> None:
    slug = "".join(c if c.isalnum() else "-" for c in name).strip("-").lower() or "startup-app"
    dest = USER_DIR / f"{slug}.desktop"
    n = 1
    while dest.exists():
        dest = USER_DIR / f"{slug}-{n}.desktop"
        n += 1
    USER_DIR.mkdir(parents=True, exist_ok=True)
    dest.write_text(f"[Desktop Entry]\nType=Application\nName={name}\nExec={exe}\n"
                    f"X-GNOME-Autostart-enabled=true\n")
    print(str(dest))


def main() -> None:
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: startup-ctl.py scan|set-enabled|remove|add …")
    cmd = args[0]
    if cmd == "scan":
        cmd_scan()
    elif cmd == "set-enabled" and len(args) == 3:
        cmd_set_enabled(args[1], args[2] == "1")
    elif cmd == "remove" and len(args) == 2:
        cmd_remove(args[1])
    elif cmd == "add" and len(args) == 3:
        cmd_add(args[1], args[2])
    else:
        sys.exit(f"bad args: {args}")


if __name__ == "__main__":
    main()
