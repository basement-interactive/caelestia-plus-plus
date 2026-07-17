#!/usr/bin/env python3
"""Desktop easter eggs: typing a trigger word while no window is focused
pops a surprise via the caelestia shell IPC (one target per egg).

Reads keyboard evdev devices directly (needs read access to /dev/input:
`input` group, or a setfacl grant). Only the last few letter keycodes
are held in memory - nothing is logged, stored, or sent anywhere.
"""

import fcntl
import json
import os
import select
import signal
import struct
import subprocess
import sys
import time

EVENT_FMT = "llHHi"  # struct input_event on 64-bit: timeval + type/code/value
EVENT_SIZE = struct.calcsize(EVENT_FMT)
EV_KEY = 1
KEY_DOWN = 1

# qwerty letter rows (KEY_Q..KEY_P, KEY_A..KEY_L, KEY_Z..KEY_M)
LETTER_CODES = set(range(16, 26)) | set(range(30, 39)) | set(range(44, 51))
# trigger word (as keycodes) -> shell IPC target to call `pop` on
SEQUENCES = {
    (25, 18, 49, 23, 31): "easterEgg",          # p-e-n-i-s
    (23, 31, 19, 30, 18, 38): "israelEgg",      # i-s-r-a-e-l
}
LONGEST_SEQUENCE = max(len(seq) for seq in SEQUENCES)

RESCAN_SECONDS = 15
COOLDOWN_SECONDS = 5


def keyboard_event_paths():
    """Devices with a kbd handler; non-keyboards there never emit letters."""
    paths = []
    with open("/proc/bus/input/devices") as f:
        for line in f:
            if line.startswith("H: Handlers=") and "kbd" in line:
                for token in line.split():
                    if token.startswith("event"):
                        paths.append("/dev/input/" + token)
    return paths


def open_keyboards(test=False):
    files = []
    for path in keyboard_event_paths():
        try:
            files.append(open(path, "rb", buffering=0))
            if test:
                print(f"[test] opened {path}", flush=True)
        except OSError as e:
            # not readable (yet) - picked up on a later rescan
            if test:
                print(f"[test] FAILED to open {path}: {e}", flush=True)
    return files


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", *args, "-j"],
                         capture_output=True, text=True, timeout=2).stdout
    return json.loads(out)


def cursor_workspace_is_empty():
    """Multi-monitor fallback: a window on another screen can hold focus
    while the user types at an empty desktop, so also accept an empty
    workspace on the monitor under the cursor."""
    try:
        cur = hyprctl_json("cursorpos")
        for m in hyprctl_json("monitors"):
            scale = m.get("scale", 1) or 1
            if m["x"] <= cur["x"] < m["x"] + m["width"] / scale \
                    and m["y"] <= cur["y"] < m["y"] + m["height"] / scale:
                ws_id = m.get("activeWorkspace", {}).get("id")
                return any(w["id"] == ws_id and w.get("windows", 1) == 0
                           for w in hyprctl_json("workspaces"))
    except (subprocess.SubprocessError, OSError, json.JSONDecodeError, KeyError):
        pass
    return False


def desktop_is_focused():
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=2).stdout
    except (subprocess.SubprocessError, OSError):
        return False
    try:
        if "address" not in json.loads(out):
            return True
    except json.JSONDecodeError:
        # hyprctl prints "Invalid" (not JSON) when nothing is focused
        if "Invalid" in out:
            return True
    return cursor_workspace_is_empty()


def pop_egg(target):
    # Never let a hung/missing qs kill the watcher — nothing restarts it
    try:
        subprocess.run(["qs", "-c", "caelestia", "ipc", "call", target, "pop"],
                       capture_output=True, timeout=5)
    except (subprocess.SubprocessError, OSError):
        pass


def matched_target(recent):
    for sequence, target in SEQUENCES.items():
        if tuple(recent[-len(sequence):]) == sequence:
            return target
    return None


def stale_watcher_pids():
    """Live watcher processes running from a different copy of this script
    (e.g. an old ~/.local/bin autostart that grabbed the lock first)."""
    me = os.path.realpath(__file__)
    try:
        out = subprocess.run(["pgrep", "-af", "penis-egg-watch"],
                             capture_output=True, text=True, timeout=2).stdout
    except (subprocess.SubprocessError, OSError):
        return []
    pids = []
    for line in out.splitlines():
        pid, _, cmd = line.partition(" ")
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        # argv[0] must BE python - a shell whose command text merely
        # mentions this script (pkill/pgrep/cp lines) must not match
        if not os.path.basename(cmd.split()[0]).startswith("python"):
            continue
        script = next((a for a in cmd.split()
                       if a.endswith("penis-egg-watch") or a.endswith("penis-egg-watch.py")), "")
        if script and os.path.realpath(script) != me:
            pids.append(int(pid))
    return pids


def acquire_single_instance_lock():
    """The shell spawns this at startup and users may also autostart a
    copy. A same-path duplicate exits like before, but a holder running
    from a DIFFERENT copy gets evicted and the lock taken over - the
    shell's post-update spawn always carries the newest sequences, and
    old copies predate this code so they can never evict back."""
    lock_dir = os.path.expanduser("~/.local/state/caelestia")
    os.makedirs(lock_dir, exist_ok=True)
    lock = open(os.path.join(lock_dir, "egg-watch.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock
    except OSError:
        pass

    stale = stale_watcher_pids()
    if not stale:
        raise SystemExit(0)
    for pid in stale:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    for _ in range(10):
        time.sleep(0.2)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return lock
        except OSError:
            continue
    raise SystemExit(0)


def main(test=False):
    # --test: no lock (runs alongside the live watcher), no pop — prints what
    # the watcher sees so "types but nothing happens" can be diagnosed
    lock = None if test else acquire_single_instance_lock()
    keyboards = open_keyboards(test)
    if test:
        print(f"[test] {len(keyboards)} device(s) open; every keypress prints below. Ctrl-C to quit", flush=True)
    recent = []
    last_scan = time.monotonic()
    last_pop = 0.0

    while True:
        if time.monotonic() - last_scan > RESCAN_SECONDS:
            # Reopen only when the device set actually changed (hotplug)
            if set(keyboard_event_paths()) != {f.name for f in keyboards}:
                for f in keyboards:
                    f.close()
                keyboards = open_keyboards()
            last_scan = time.monotonic()

        if not keyboards:
            time.sleep(RESCAN_SECONDS)
            last_scan = 0
            continue

        readable, _, _ = select.select(keyboards, [], [], RESCAN_SECONDS)
        for f in readable:
            try:
                data = f.read(EVENT_SIZE * 64)
            except OSError:
                keyboards.remove(f)
                f.close()
                continue
            if not data:
                continue

            for i in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, etype, code, value = struct.unpack_from(EVENT_FMT, data, i)
                if etype != EV_KEY or value != KEY_DOWN:
                    continue
                if test:
                    print(f"[test] keydown code={code} {'letter' if code in LETTER_CODES else 'other'} from {f.name}", flush=True)
                if code not in LETTER_CODES:
                    recent.clear()
                    continue
                recent.append(code)
                del recent[:-LONGEST_SEQUENCE]
                target = matched_target(recent)
                if target is None:
                    continue
                if test:
                    print(f"[test] SEQUENCE DETECTED ({target}); gate desktop_is_focused() = {desktop_is_focused()}", flush=True)
                    recent.clear()
                    continue
                if time.monotonic() - last_pop > COOLDOWN_SECONDS:
                    recent.clear()
                    if desktop_is_focused():
                        last_pop = time.monotonic()
                        pop_egg(target)


if __name__ == "__main__":
    main(test="--test" in sys.argv)
