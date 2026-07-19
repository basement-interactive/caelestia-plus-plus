#!/usr/bin/env python3
"""redguardd - behavioral process protection daemon.

A lightweight HIPS for this Caelestia setup. It watches process execs in real
time via the kernel's netlink proc-connector (no polling, no eBPF toolchain)
and, on a high-confidence detection, FREEZES the process (SIGSTOP) and asks the
user through the bar: allow, block, or allow once. The decision is remembered
per-executable and persisted, so it survives reboots.

It is a companion to redwall (the network firewall): redwall governs who may
talk to the network, redguard governs whether a process is behaving like an
exploit payload. It touches no networking at all, so it is completely
VPN-agnostic.

Detections (deliberately narrow, to keep false positives near zero):

  reverse-shell   An interpreter/shell (bash, python, perl, nc, socat, …) whose
                  standard in/out/err is wired to a *network* socket. This is
                  the canonical reverse-shell signature and essentially never
                  happens for legitimate interactive shells (whose stdio is a
                  pty) or pipelines (whose stdio is a pipe).

  foreign-exec    A process whose executable file itself lives in a world-
                  writable scratch dir (/tmp, /dev/shm, /var/tmp, /run/user) or
                  has been deleted/anonymised (memfd, unlinked binary) while
                  running. The classic "dropper writes payload, runs it" and
                  in-memory-only malware pattern. Known-safe cases (AppImage
                  mounts, browser sandboxes, systemd-private) are excluded.

The parent process is reported for context (e.g. "spawned by firefox"), which
sharpens an RCE story, but it is never a trigger on its own — a browser opening
a link legitimately runs helper shells (xdg-open), so parent lineage alone
would be a false-positive machine.

Safety / honesty:
- Best-effort, not a kernel-enforced sandbox. There is a small window between
  exec and freeze; for the interactive payloads this targets (a reverse shell
  waiting for commands, a dropper about to act) the freeze lands in time.
- Fails OPEN: if the bar UI is not connected there is no one to ask, so a
  frozen process is released and logged rather than left stuck forever. So
  protection is only enforced while the shell is running (it is the desktop).
- A quick pre-filter means only interpreters and scratch-dir/deleted exes are
  ever frozen for inspection; everything else is never touched (near-zero
  overhead and zero interruption for normal programs).

Run with --simulate to exercise the rule engine + UI protocol with synthetic
detections (no root, no netlink).
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import socket
import struct
import threading
import time
from pathlib import Path

SOCK_PATH = "/run/redguard/ui.sock"
RULES_PATH = "/var/lib/redguard/rules.json"

# Interpreters/shells worth inspecting. A reverse shell is almost always one of
# these; a normal one has pty/pipe stdio and is released instantly.
INTERPRETERS = {
    "bash", "sh", "dash", "zsh", "ksh", "fish", "ash", "busybox",
    "python", "python2", "python3", "perl", "ruby", "php", "lua", "luajit",
    "node", "deno", "tclsh", "expect", "awk", "gawk", "mawk",
    "nc", "ncat", "netcat", "socat", "telnet", "socket",
}

# Executable-path prefixes that sit in scratch space but are known-safe: their
# presence there is normal, not a dropper. Kept tight on purpose.
SAFE_TMP_PREFIXES = (
    "/tmp/.mount_",            # AppImage FUSE mounts
    "/tmp/.org.chromium.",     # Chromium/Electron sandbox helpers
    "/tmp/.io.",               # some Flatpak/portal helpers
    "/tmp/appimage",           # AppImage extraction
)
SCRATCH_DIRS = ("/tmp/", "/var/tmp/", "/dev/shm/", "/run/user/")


# --------------------------------------------------------------------------- #
# Rule store (per-executable verdicts), mirrors redwall's                      #
# --------------------------------------------------------------------------- #
class Rules:
    def __init__(self, path: str):
        self._path = Path(path)
        self._lock = threading.Lock()
        self._data: dict[str, dict] = {}
        self.load()

    def load(self) -> None:
        try:
            self._data = json.loads(self._path.read_text())
        except (OSError, json.JSONDecodeError):
            self._data = {}

    def save(self) -> None:
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._data, indent=2))
            tmp.replace(self._path)
        except OSError as e:
            print(f"[redguard] rule save failed: {e}", flush=True)

    def action_for(self, exe: str) -> str | None:
        with self._lock:
            return (self._data.get(exe) or {}).get("action")

    def set(self, exe: str, action: str, name: str | None = None) -> None:
        with self._lock:
            entry = self._data.get(exe, {})
            entry.update(action=action, name=name or entry.get("name") or Path(exe).name,
                         added=entry.get("added") or time.time())
            self._data[exe] = entry
            self.save()

    def delete(self, exe: str) -> None:
        with self._lock:
            self._data.pop(exe, None)
            self.save()

    def snapshot(self) -> list[dict]:
        with self._lock:
            return [{"exe": k, **v} for k, v in self._data.items()]


# --------------------------------------------------------------------------- #
# Process inspection helpers (/proc)                                           #
# --------------------------------------------------------------------------- #
def _comm(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        return ""


def _exe(pid: int) -> tuple[str, bool]:
    """Return (resolved_exe, deleted). deleted covers unlinked/memfd binaries."""
    try:
        link = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return "", False
    deleted = link.endswith(" (deleted)") or link.startswith("/memfd:")
    real = link[:-10] if link.endswith(" (deleted)") else link
    return real, deleted


def _ppid(pid: int) -> int:
    try:
        # /proc/pid/stat: comm is parenthesised and may contain spaces, so slice
        # after the last ')' — ppid is the 2nd field beyond it.
        data = Path(f"/proc/{pid}/stat").read_text()
        after = data[data.rindex(")") + 2:].split()
        return int(after[1])
    except (OSError, ValueError, IndexError):
        return 0


def _net_socket_inodes() -> set[str]:
    inodes = set()
    for fam in ("tcp", "tcp6", "udp", "udp6"):
        try:
            for line in Path(f"/proc/net/{fam}").read_text().splitlines()[1:]:
                f = line.split()
                if len(f) >= 10:
                    inodes.add(f[9])
        except OSError:
            continue
    return inodes


def _stdio_on_network_socket(pid: int, net_inodes: set[str]) -> bool:
    """True if fd 0/1/2 of pid is a network (not unix/pipe) socket."""
    for fd in (0, 1, 2):
        try:
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if link.startswith("socket:[") and link[8:-1] in net_inodes:
            return True
    return False


def _in_scratch(exe: str) -> bool:
    if not exe or any(exe.startswith(p) for p in SAFE_TMP_PREFIXES):
        return False
    return any(exe.startswith(d) for d in SCRATCH_DIRS)


# --------------------------------------------------------------------------- #
# Daemon                                                                        #
# --------------------------------------------------------------------------- #
class Redguard:
    def __init__(self, rules: Rules, simulate: bool, ui_gid: int, state_path: str):
        self.rules = rules
        self.simulate = simulate
        self.ui_gid = ui_gid
        self.state_path = Path(state_path)
        self.enabled = self._load_enabled()
        self.loop: asyncio.AbstractEventLoop | None = None
        self.clients: set[asyncio.StreamWriter] = set()
        self._lock = threading.Lock()
        self.self_pid = os.getpid()
        # id -> {pid, exe, name, kind, parent, detail, ts}
        self.pending: dict[int, dict] = {}
        self._next_id = 1

    def _load_enabled(self) -> bool:
        try:
            return bool(json.loads(self.state_path.read_text()).get("enabled", True))
        except (OSError, json.JSONDecodeError):
            return True

    def set_enabled(self, value: bool) -> None:
        self.enabled = value
        try:
            self.state_path.parent.mkdir(parents=True, exist_ok=True)
            self.state_path.write_text(json.dumps({"enabled": value}))
        except OSError as e:
            print(f"[redguard] state save failed: {e}", flush=True)
        if not value:
            # Disabling releases everything currently frozen.
            with self._lock:
                held = list(self.pending.values())
                self.pending.clear()
            for entry in held:
                self._cont(entry["pid"])
                self.broadcast_threadsafe({"t": "resolved", "id": entry["id"]})
        self.broadcast_threadsafe({"t": "state", "enabled": value})

    # -- signals ------------------------------------------------------------ #
    @staticmethod
    def _stop(pid: int) -> bool:
        try:
            os.kill(pid, signal.SIGSTOP)
            return True
        except OSError:
            return False

    @staticmethod
    def _cont(pid: int) -> None:
        try:
            os.kill(pid, signal.SIGCONT)
        except OSError:
            pass

    @staticmethod
    def _kill(pid: int) -> None:
        # Kill the whole group where possible (payloads spawn children), then
        # the pid itself. SIGCONT first so a stopped process can actually die.
        for sig in (signal.SIGCONT, signal.SIGKILL):
            try:
                os.killpg(os.getpgid(pid), sig)
            except OSError:
                try:
                    os.kill(pid, sig)
                except OSError:
                    pass

    # -- UI messaging (mirrors redwall) ------------------------------------- #
    def _broadcast(self, msg: dict) -> None:
        data = (json.dumps(msg) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(data)
            except Exception:
                self.clients.discard(w)

    def broadcast_threadsafe(self, msg: dict) -> None:
        if self.loop:
            self.loop.call_soon_threadsafe(self._broadcast, msg)

    def push_rules(self) -> None:
        self.broadcast_threadsafe({"t": "rules", "rules": self.rules.snapshot()})

    def clients_connected(self) -> bool:
        return len(self.clients) > 0

    # -- classification ----------------------------------------------------- #
    def classify(self, pid: int) -> dict | None:
        """Return a detection dict for pid, or None if it looks benign.
        Reads /proc only — safe to call on a running (unfrozen) process."""
        comm = _comm(pid)
        exe, deleted = _exe(pid)
        is_interp = comm in INTERPRETERS or Path(exe).name in INTERPRETERS

        if deleted:
            kind, detail = "foreign-exec", "runs from a deleted/anonymous executable (in-memory payload)"
        elif _in_scratch(exe):
            kind, detail = "foreign-exec", f"executable lives in a world-writable scratch dir: {exe}"
        elif is_interp and _stdio_on_network_socket(pid, _net_socket_inodes()):
            kind, detail = "reverse-shell", "an interpreter with its input/output wired to a network socket"
        else:
            return None

        ppid = _ppid(pid)
        parent = _comm(ppid) if ppid else ""
        name = comm or (Path(exe).name if exe else f"pid {pid}")
        return {"pid": pid, "exe": exe or f"(pid {pid})", "name": name,
                "kind": kind, "parent": parent, "detail": detail}

    # -- exec event (called from netlink thread) ---------------------------- #
    def on_exec(self, pid: int) -> None:
        if not self.enabled or pid == self.self_pid or pid <= 1:
            return
        comm = _comm(pid)
        exe, deleted = _exe(pid)
        # Pre-filter: only interpreters and scratch/deleted exes are candidates.
        # Everything else is never frozen — normal programs run untouched.
        candidate = deleted or _in_scratch(exe) or comm in INTERPRETERS or \
            (exe and Path(exe).name in INTERPRETERS)
        if not candidate:
            return

        # A persisted verdict short-circuits before any freeze.
        action = self.rules.action_for(exe) if exe else None
        if action == "allow":
            return
        if action == "block":
            self._kill(pid)
            self.broadcast_threadsafe({"t": "event", "name": comm or exe,
                                       "kind": "blocked", "detail": f"auto-blocked {exe}"})
            return

        # Classify BEFORE freezing: SIGSTOP on a foreground job makes the
        # user's shell reclaim the terminal ("suspended (signal)") even when
        # SIGCONT follows within milliseconds — and the interpreter pre-filter
        # covers every /usr/bin wrapper script. Benign execs (the overwhelming
        # majority) must never be signalled at all; a real payload runs a few
        # extra ms before the freeze, which the kill/ask flow still contains.
        detection = self.classify(pid)
        if detection is None:
            return

        # Detection: freeze now, then re-classify — the process ran unfrozen
        # and may have exited or exec'd into something else meanwhile.
        if not self._stop(pid):
            return
        detection = self.classify(pid)
        if detection is None:
            self._cont(pid)
            return

        # Fail open: nobody to ask -> release and log rather than hang forever.
        if not self.clients_connected():
            self._cont(pid)
            self.broadcast_threadsafe({"t": "event", "kind": "unmonitored", **detection})
            print(f"[redguard] released (no UI): {detection}", flush=True)
            return

        with self._lock:
            ask_id = self._next_id
            self._next_id += 1
            detection["id"] = ask_id
            detection["ts"] = time.time()
            self.pending[ask_id] = detection
        self.broadcast_threadsafe({"t": "ask", **detection})

    # -- verdicts ----------------------------------------------------------- #
    def apply_verdict(self, ask_id: int, action: str, remember: bool) -> None:
        with self._lock:
            entry = self.pending.pop(ask_id, None)
        if not entry:
            return
        pid, exe = entry["pid"], entry["exe"]
        if action == "block":
            self._kill(pid)
        else:  # allow / once
            self._cont(pid)
        if remember and action in ("allow", "block") and exe.startswith("/"):
            self.rules.set(exe, action, entry.get("name"))
            self.push_rules()
        self.broadcast_threadsafe({"t": "resolved", "id": ask_id})

    # -- UI socket server (identical contract to redwall) ------------------- #
    def _authorized(self, writer: asyncio.StreamWriter) -> bool:
        sock = writer.get_extra_info("socket")
        if sock is None:
            return False
        try:
            creds = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
            pid, uid, gid = struct.unpack("3i", creds)
        except OSError:
            return False
        if uid == 0 or gid == self.ui_gid:
            return True
        try:
            for line in Path(f"/proc/{pid}/status").read_text().splitlines():
                if line.startswith("Groups:"):
                    if self.ui_gid in (int(g) for g in line.split()[1:]):
                        return True
                    break
        except (OSError, ValueError):
            pass
        print(f"[redguard] rejected UI connection uid={uid} gid={gid} pid={pid}", flush=True)
        return False

    async def _serve_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        if not self._authorized(writer):
            try:
                writer.close()
            except Exception:
                pass
            return
        self.clients.add(writer)
        writer.write((json.dumps({"t": "rules", "rules": self.rules.snapshot()}) + "\n").encode())
        writer.write((json.dumps({"t": "state", "enabled": self.enabled}) + "\n").encode())
        with self._lock:
            waiting = [{"t": "ask", **p} for p in self.pending.values()]
        for m in waiting:
            writer.write((json.dumps(m) + "\n").encode())
        try:
            await writer.drain()
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                try:
                    self._on_ui_message(msg)
                except (KeyError, ValueError, TypeError) as e:
                    print(f"[redguard] ignoring malformed UI message: {e}", flush=True)
        except (ConnectionError, OSError, asyncio.IncompleteReadError):
            pass
        finally:
            self.clients.discard(writer)
            try:
                writer.close()
            except Exception:
                pass

    def _on_ui_message(self, msg: dict) -> None:
        t = msg.get("t")
        if t == "verdict":
            self.apply_verdict(int(msg["id"]), msg.get("action", "block"), bool(msg.get("remember", True)))
        elif t == "setrule":
            self.rules.set(msg["exe"], msg.get("action", "block"), msg.get("name"))
            self.push_rules()
        elif t == "delrule":
            self.rules.delete(msg["exe"])
            self.push_rules()
        elif t == "getrules":
            self.push_rules()
        elif t == "setenabled":
            self.set_enabled(bool(msg.get("enabled", True)))
        elif t == "simdetect" and self.simulate:
            self._sim_inject(msg)

    async def run_server(self) -> None:
        self.loop = asyncio.get_running_loop()
        os.makedirs(os.path.dirname(SOCK_PATH), exist_ok=True)
        try:
            os.unlink(SOCK_PATH)
        except FileNotFoundError:
            pass
        server = await asyncio.start_unix_server(self._serve_client, path=SOCK_PATH)
        try:
            os.chown(SOCK_PATH, 0, self.ui_gid)
        except (PermissionError, OSError):
            pass
        os.chmod(SOCK_PATH, 0o660)
        async with server:
            await server.serve_forever()

    # -- simulate ----------------------------------------------------------- #
    def _sim_inject(self, msg: dict) -> None:
        with self._lock:
            ask_id = self._next_id
            self._next_id += 1
            entry = {"id": ask_id, "pid": int(msg.get("pid", 0)),
                     "exe": msg.get("exe", "/tmp/payload"), "name": msg.get("name", "payload"),
                     "kind": msg.get("kind", "reverse-shell"), "parent": msg.get("parent", "firefox"),
                     "detail": msg.get("detail", "simulated detection"), "ts": time.time()}
            self.pending[ask_id] = entry
        self.broadcast_threadsafe({"t": "ask", **entry})

    async def _sim_seed(self) -> None:
        await asyncio.sleep(1.5)
        samples = [
            {"exe": "/tmp/.x/beacon", "name": "beacon", "kind": "foreign-exec", "parent": "firefox",
             "detail": "executable lives in a world-writable scratch dir: /tmp/.x/beacon"},
            {"exe": "/usr/bin/bash", "name": "bash", "kind": "reverse-shell", "parent": "python3",
             "detail": "an interpreter with its input/output wired to a network socket"},
        ]
        for s in samples:
            if self.clients_connected():
                self._sim_inject(s)
                await asyncio.sleep(0.4)


# --------------------------------------------------------------------------- #
# netlink proc-connector: real-time exec events                                #
# --------------------------------------------------------------------------- #
def proc_connector_thread(guard: Redguard) -> None:
    NETLINK_CONNECTOR = 11
    CN_IDX_PROC = 1
    CN_VAL_PROC = 1
    PROC_CN_MCAST_LISTEN = 1
    PROC_EVENT_EXEC = 0x00000002

    try:
        sk = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, NETLINK_CONNECTOR)
        sk.bind((os.getpid(), CN_IDX_PROC))
    except OSError as e:
        print(f"[redguard] cannot open proc connector (need root/CAP_NET_ADMIN): {e}", flush=True)
        return

    # Subscribe: nlmsghdr + cn_msg + u32(PROC_CN_MCAST_LISTEN)
    op = struct.pack("=I", PROC_CN_MCAST_LISTEN)
    cn_msg = struct.pack("=IIIIHH", CN_IDX_PROC, CN_VAL_PROC, 0, 0, len(op), 0) + op
    nlmsg = struct.pack("=IHHII", 16 + len(cn_msg), 3, 0, 0, os.getpid()) + cn_msg  # type 3 = NLMSG_DONE
    try:
        sk.send(nlmsg)
    except OSError as e:
        print(f"[redguard] proc connector subscribe failed: {e}", flush=True)
        return

    print("[redguard] proc connector active", flush=True)
    while True:
        try:
            data = sk.recv(1024)
        except OSError:
            continue
        # nlmsghdr(16) + cn_msg(20) then proc_event: what(I) cpu(I) ts(Q) then data
        if len(data) < 16 + 20 + 16 + 8:
            continue
        base = 16 + 20
        (what,) = struct.unpack_from("=I", data, base)
        if what != PROC_EVENT_EXEC:
            continue
        # exec_proc_event: process_pid(i), process_tgid(i) after the 16-byte head
        pid, tgid = struct.unpack_from("=ii", data, base + 16)
        try:
            guard.on_exec(pid)
        except Exception as e:  # a bug in classification must never kill the monitor
            print(f"[redguard] on_exec error for pid {pid}: {e}", flush=True)


# --------------------------------------------------------------------------- #
def main() -> None:
    global SOCK_PATH, RULES_PATH
    ap = argparse.ArgumentParser()
    ap.add_argument("--simulate", action="store_true",
                    help="no netlink/root; inject synthetic detections for UI testing")
    ap.add_argument("--sock", default=SOCK_PATH)
    ap.add_argument("--rules", default=RULES_PATH)
    ap.add_argument("--ui-gid", type=int, default=1000)
    args = ap.parse_args()
    SOCK_PATH, RULES_PATH = args.sock, args.rules

    guard = Redguard(Rules(args.rules), args.simulate, args.ui_gid,
                     str(Path(args.rules).parent / "state.json"))

    if not args.simulate:
        threading.Thread(target=proc_connector_thread, args=(guard,), daemon=True).start()

    async def _run():
        tasks = [asyncio.create_task(guard.run_server())]
        if args.simulate:
            tasks.append(asyncio.create_task(guard._sim_seed()))
        await asyncio.gather(*tasks)

    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
