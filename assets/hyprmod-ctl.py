#!/usr/bin/env python3
"""Bridge between the Caelestia++ settings UI and HyprMod's variables.lua.

dump            print scalar knobs as JSON: {key: value, ...}
set KEY VALUE   rewrite the knob line in variables.lua, then apply live:
                instantly via socket `eval hl.config(...)` when the knob maps
                to a config path, otherwise via a compositor `reload`.

Only scalar knobs (bool / number / string literals) are managed; computed
entries like the border gradients stay lua-only.
"""

import glob
import json
import os
import re
import socket
import subprocess
import sys

VARIABLES = os.path.expanduser("~/.config/hypr/variables.lua")

KNOB_LINE = re.compile(r"^(\s*)(\w+)(\s*=\s*)(.+?)(,\s*)$")

# Knobs that hyprland/*.lua feed straight into hl.config — these apply
# instantly over the socket. Everything else needs a compositor reload
# (keybinds, gestures, exec-time values).
EVAL_PATHS = {
    "blurEnabled": "decoration.blur.enabled",
    "blurXray": "decoration.blur.xray",
    "blurSpecialWs": "decoration.blur.special",
    "blurPopups": "decoration.blur.popups",
    "blurInputMethods": "decoration.blur.input_methods",
    "blurSize": "decoration.blur.size",
    "blurPasses": "decoration.blur.passes",
    "shadowEnabled": "decoration.shadow.enabled",
    "shadowRange": "decoration.shadow.range",
    "shadowRenderPower": "decoration.shadow.render_power",
    "windowRounding": "decoration.rounding",
    "workspaceGaps": "general.gaps_workspaces",
    "windowGapsIn": "general.gaps_in",
    "windowGapsOut": "general.gaps_out",
    "windowBorderSize": "general.border_size",
    "touchpadDisableTyping": "input.touchpad.disable_while_typing",
    "touchpadScrollFactor": "input.touchpad.scroll_factor",
}


def parse_scalar(raw: str):
    if raw == "true":
        return True
    if raw == "false":
        return False
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if re.fullmatch(r"-?\d*\.\d+", raw):
        return float(raw)
    m = re.fullmatch(r'"([^"]*)"', raw)
    if m:
        return m.group(1)
    return None  # computed / table — not ours


def to_lua(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return f"{value:g}"
    return f'"{value}"'


def read_knobs() -> dict:
    knobs = {}
    for line in open(VARIABLES):
        m = KNOB_LINE.match(line.rstrip("\n"))
        if m:
            value = parse_scalar(m.group(4).strip())
            if value is not None:
                knobs[m.group(2)] = value
    return knobs


def write_knob(key: str, value) -> None:
    lines = open(VARIABLES).readlines()
    for i, line in enumerate(lines):
        m = KNOB_LINE.match(line.rstrip("\n"))
        if m and m.group(2) == key:
            lines[i] = f"{m.group(1)}{key}{m.group(3)}{to_lua(value)}{m.group(5)}\n"
            break
    else:
        sys.exit(f"unknown knob: {key}")
    with open(VARIABLES, "w") as f:
        f.writelines(lines)


def hypr_socket() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if signature:
        return f"{runtime}/hypr/{signature}/.socket.sock"
    candidates = glob.glob(f"{runtime}/hypr/*/.socket.sock")
    if not candidates:
        sys.exit("no hyprland socket")
    return max(candidates, key=os.path.getmtime)


def send(command: str) -> str:
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(hypr_socket())
        s.sendall(command.encode())
        return s.recv(8192).decode()


def apply_live(key: str, value) -> None:
    if key == "cursorTheme" or key == "cursorSize":
        knobs = read_knobs()
        subprocess.run(["hyprctl", "setcursor", str(knobs["cursorTheme"]), str(knobs["cursorSize"])])
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", str(knobs["cursorTheme"])])
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(knobs["cursorSize"])])
        return

    path = EVAL_PATHS.get(key)
    if path:
        table = to_lua(value)
        for part in reversed(path.split(".")):
            table = f"{{{part}={table}}}"
        send(f"eval hl.config({table})")
    else:
        send("reload")


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "dump":
        print(json.dumps(read_knobs()))
    elif len(sys.argv) == 4 and sys.argv[1] == "set":
        key, raw = sys.argv[2], sys.argv[3]
        current = read_knobs().get(key)
        if current is None:
            sys.exit(f"unknown or non-scalar knob: {key}")
        if isinstance(current, bool):
            value = raw == "true"
        elif isinstance(current, (int, float)):
            value = float(raw) if "." in raw else int(raw)
        else:
            value = raw
        write_knob(key, value)
        apply_live(key, value)
    else:
        sys.exit(__doc__.strip())


if __name__ == "__main__":
    main()
