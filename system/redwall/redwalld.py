#!/usr/bin/env python3
"""redwalld - per-application interactive outbound firewall daemon.

SimpleWall-style: the first time an executable tries to open a new outbound
connection it is held at the kernel (NFQUEUE) while the user is prompted to
allow or deny it. The decision is remembered per-executable and persisted, so
it survives reboots (the daemon runs as a systemd service).

Design / safety:
- nftables `inet` table hooks OUTPUT, exempts loopback / established / DNS, and
  sends only NEW outbound connections to NFQUEUE `num` with `bypass` set, so if
  this daemon is not running the kernel fails OPEN (normal networking) rather
  than cutting the machine off.
- Attribution happens while the SYN is held, so the owning socket is still live
  in /proc: local port -> inode (/proc/net/{tcp,tcp6,udp,udp6}) -> pid
  (/proc/*/fd) -> exe (/proc/pid/exe). Covers IPv4 and IPv6.
- Prompts are deduped per-executable: retransmitted SYNs and parallel
  connections from an unknown app produce one popup, and the verdict is applied
  to every held packet for that exe.
- The UI (a Quickshell widget) speaks newline-delimited JSON over a Unix socket.
  No UI connected => fail open (never brick networking when the bar is down).

Run `redwalld.py --simulate` to exercise the whole rule engine + UI protocol
with synthetic connection events, no root and no NFQUEUE. That mode is for
verifying the UI; real enforcement uses the default NFQUEUE mode under the
systemd unit installed by install.sh.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import socket
import struct
import subprocess
import threading
import time
from pathlib import Path

QUEUE_NUM = 0
SOCK_PATH = "/run/redwall/ui.sock"
RULES_PATH = "/var/lib/redwall/rules.json"
NFT_TABLE = "redwall"

IPPROTO = {6: "tcp", 17: "udp"}


# --------------------------------------------------------------------------- #
# Rule store                                                                   #
# --------------------------------------------------------------------------- #
class Rules:
    """Persistent per-executable verdicts: {exe: {action, name, added}}."""

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

    def has_deny(self) -> bool:
        with self._lock:
            return any(v.get("action") == "deny" for v in self._data.values())

    def save(self) -> None:
        # A failed persist must never take down live filtering.
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._data, indent=2))
            tmp.replace(self._path)
        except OSError as e:
            print(f"[redwall] rule save failed: {e}", flush=True)

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
# Packet parsing (IPv4 + IPv6)                                                 #
# --------------------------------------------------------------------------- #
def parse_packet(payload: bytes):
    """Return (proto, saddr, sport, daddr, dport) or None if not TCP/UDP."""
    if not payload:
        return None
    version = payload[0] >> 4
    if version == 4:
        ihl = (payload[0] & 0x0F) * 4
        proto = payload[9]
        saddr = socket.inet_ntop(socket.AF_INET, payload[12:16])
        daddr = socket.inet_ntop(socket.AF_INET, payload[16:20])
        l4 = payload[ihl:]
    elif version == 6:
        proto = payload[6]  # next header; good enough for bare TCP/UDP SYNs
        saddr = socket.inet_ntop(socket.AF_INET6, payload[8:24])
        daddr = socket.inet_ntop(socket.AF_INET6, payload[24:40])
        l4 = payload[40:]
    else:
        return None
    if proto not in IPPROTO or len(l4) < 4:
        return None
    sport, dport = struct.unpack("!HH", l4[:4])
    return IPPROTO[proto], saddr, sport, daddr, dport


# --------------------------------------------------------------------------- #
# Attribution: local port -> inode -> pid -> exe                               #
# --------------------------------------------------------------------------- #
def _inode_by_local_port(proto: str, sport: int) -> int | None:
    for fam in (proto, proto + "6"):
        try:
            lines = Path(f"/proc/net/{fam}").read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            f = line.split()
            if len(f) < 10:
                continue
            local = f[1]  # HEXADDR:HEXPORT
            try:
                port = int(local.rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port == sport:
                try:
                    return int(f[9])
                except ValueError:
                    return None
    return None


def _pid_for_inode(inode: int) -> int | None:
    target = f"socket:[{inode}]"
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fddir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fddir):
                try:
                    if os.readlink(f"{fddir}/{fd}") == target:
                        return int(pid)
                except OSError:
                    continue
        except OSError:
            continue
    return None


def attribute(proto: str, sport: int):
    """Return (exe, name, pid) for the socket owning local port sport."""
    inode = _inode_by_local_port(proto, sport)
    if inode is None:
        return None
    pid = _pid_for_inode(inode)
    if pid is None:
        return None
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return None
    if not exe or exe == f"/proc/{pid}/exe":
        return None
    try:
        cmd = Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        cmd = Path(exe).name
    return exe, cmd, pid


def _run(cmd: list[str]) -> None:
    """Best-effort external command; never raises into the caller."""
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


# --------------------------------------------------------------------------- #
# Daemon                                                                        #
# --------------------------------------------------------------------------- #
class Redwall:
    def __init__(self, rules: Rules, simulate: bool, ui_gid: int, state_path: str):
        self.rules = rules
        self.simulate = simulate
        self.ui_gid = ui_gid
        self.state_path = Path(state_path)
        self.enabled = self._load_enabled()
        self.loop: asyncio.AbstractEventLoop | None = None
        self.clients: set[asyncio.StreamWriter] = set()
        self._lock = threading.Lock()
        # exe -> {"id", "name", "dst", "port", "proto", "pkts": [pkt...], "ts"}
        self.pending: dict[str, dict] = {}
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
            print(f"[redwall] state save failed: {e}", flush=True)
        if not value:
            # Disabling passes everything, so release anything held right now
            # (accept the packets, dismiss the popups) instead of leaving it stuck.
            with self._lock:
                held = list(self.pending.keys())
            for exe in held:
                self._resolve(exe, True)
                self.broadcast_threadsafe({"t": "resolved", "exe": exe})
        self.broadcast_threadsafe({"t": "state", "enabled": value})

    # -- UI messaging ------------------------------------------------------- #
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

    # -- verdict resolution ------------------------------------------------- #
    def _resolve(self, exe: str, allow: bool) -> None:
        """Verdict every held packet for exe."""
        with self._lock:
            entry = self.pending.pop(exe, None)
        if not entry:
            return
        for pkt in entry["pkts"]:
            try:
                pkt.accept() if allow else pkt.drop()
            except Exception:
                pass

    def apply_verdict(self, ask_id: int, action: str, remember: bool) -> None:
        exe = None
        with self._lock:
            for e, p in self.pending.items():
                if p["id"] == ask_id:
                    exe = e
                    break
        if exe is None:
            return
        allow = action == "allow"
        if remember:
            self.rules.set(exe, action, self.pending.get(exe, {}).get("name"))
            self.push_rules()
        self._resolve(exe, allow)
        if not allow:
            self._cut_connections(exe)
        self.broadcast_threadsafe({"t": "resolved", "exe": exe})

    def _sockets_for_exe(self, exe: str) -> list:
        """(proto, local_port) for every socket currently owned by exe."""
        inodes = set()
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                if os.path.realpath(f"/proc/{pid}/exe") != exe:
                    continue
            except OSError:
                continue
            try:
                for fd in os.listdir(f"/proc/{pid}/fd"):
                    try:
                        link = os.readlink(f"/proc/{pid}/fd/{fd}")
                    except OSError:
                        continue
                    if link.startswith("socket:["):
                        inodes.add(link[8:-1])
            except OSError:
                continue
        if not inodes:
            return []
        conns = []
        for proto, fam in (("tcp", "tcp"), ("tcp", "tcp6"), ("udp", "udp"), ("udp", "udp6")):
            try:
                lines = Path(f"/proc/net/{fam}").read_text().splitlines()[1:]
            except OSError:
                continue
            for line in lines:
                f = line.split()
                if len(f) < 10 or f[9] not in inodes:
                    continue
                try:
                    lport = int(f[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                conns.append((proto, lport))
        return conns

    def _cut_connections(self, exe: str) -> None:
        """Tear down an app's live connections so a deny bites immediately."""
        conns = self._sockets_for_exe(exe)
        if not conns:
            return

        def worker():
            for proto, lport in conns:
                if proto == "tcp":
                    _run(["ss", "-K", f"sport = :{lport}"])  # RST the socket now
                _run(["conntrack", "-D", "-p", proto, "--orig-port-src", str(lport)])

        threading.Thread(target=worker, daemon=True).start()

    # -- core decision (called from NFQUEUE thread) ------------------------- #
    def handle(self, pkt, meta: dict) -> None:
        """meta: {exe,name,dst,port,proto,pid}. Decide accept/hold/drop."""
        if not self.enabled:
            pkt.accept()  # firewall disabled: pass everything, rules retained
            return
        exe = meta["exe"]
        action = self.rules.action_for(exe)
        if action == "allow":
            pkt.accept()
            return
        if action == "deny":
            pkt.drop()
            return
        # DNS: never prompt (would stall name resolution). A denied app was
        # already dropped above, so this only lets allowed/unknown apps resolve.
        if meta["port"] == 53:
            pkt.accept()
            return
        # Unknown app: hold and prompt (deduped per-exe).
        with self._lock:
            if not self.clients_connected():
                pkt.accept()  # fail open: no UI to ask
                return
            entry = self.pending.get(exe)
            if entry:
                entry["pkts"].append(pkt)  # dedupe: same app, one prompt
                return
            ask_id = self._next_id
            self._next_id += 1
            self.pending[exe] = {"id": ask_id, "pkts": [pkt], "ts": time.time(), **meta}
        self.broadcast_threadsafe({"t": "ask", "id": ask_id, **meta})

    def clients_connected(self) -> bool:
        return len(self.clients) > 0

    # -- UI socket server --------------------------------------------------- #
    async def _serve_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        self.clients.add(writer)
        writer.write((json.dumps({"t": "rules", "rules": self.rules.snapshot()}) + "\n").encode())
        writer.write((json.dumps({"t": "state", "enabled": self.enabled}) + "\n").encode())
        # Replay any prompts already waiting so a freshly-launched bar catches up.
        with self._lock:
            waiting = [{"t": "ask", "id": p["id"], "exe": e, "name": p["name"],
                        "dst": p["dst"], "port": p["port"], "proto": p["proto"]}
                       for e, p in self.pending.items()]
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
                self._on_ui_message(msg)
        except (ConnectionError, OSError, asyncio.IncompleteReadError):
            pass  # client vanished (shell reload); nothing to do
        finally:
            self.clients.discard(writer)
            try:
                writer.close()
            except Exception:
                pass

    def _on_ui_message(self, msg: dict) -> None:
        t = msg.get("t")
        if t == "verdict":
            self.apply_verdict(int(msg["id"]), msg.get("action", "deny"),
                               bool(msg.get("remember", True)))
        elif t == "setrule":
            exe, action = msg["exe"], msg.get("action", "deny")
            self.rules.set(exe, action, msg.get("name"))
            # If that app is currently waiting, decide it now too.
            with self._lock:
                waiting = exe in self.pending
            if waiting:
                self._resolve(exe, action == "allow")
                self.broadcast_threadsafe({"t": "resolved", "exe": exe})
            # Denying: kill the app's live connections so it stops immediately.
            if action == "deny":
                self._cut_connections(exe)
            self.push_rules()
        elif t == "delrule":
            self.rules.delete(msg["exe"])
            self.push_rules()
        elif t == "getrules":
            self.push_rules()
        elif t == "setenabled":
            self.set_enabled(bool(msg.get("enabled", True)))
        elif t == "simconnect" and self.simulate:
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

    # -- simulate mode ------------------------------------------------------ #
    class _FakePkt:
        def __init__(self, tag): self.tag = tag
        def accept(self): print(f"[sim] ACCEPT {self.tag}", flush=True)
        def drop(self): print(f"[sim] DROP {self.tag}", flush=True)

    def _sim_inject(self, msg: dict) -> None:
        exe = msg.get("exe", "/usr/bin/unknownapp")
        meta = {"exe": exe, "name": msg.get("name", Path(exe).name),
                "dst": msg.get("dst", "203.0.113.7"), "port": int(msg.get("port", 443)),
                "proto": msg.get("proto", "tcp"), "pid": int(msg.get("pid", 0))}
        self.handle(self._FakePkt(exe), meta)

    async def _sim_seed(self) -> None:
        await asyncio.sleep(1.5)
        samples = [
            {"exe": "/usr/lib/firefox/firefox", "name": "firefox", "dst": "34.117.65.55", "port": 443},
            {"exe": "/usr/bin/Discord", "name": "Discord", "dst": "162.159.130.234", "port": 443},
            {"exe": "/opt/some-telemetry/tracker", "name": "tracker", "dst": "8.8.8.8", "port": 4444, "proto": "udp"},
        ]
        for s in samples:
            if self.clients_connected():
                self._sim_inject(s)
                await asyncio.sleep(0.3)


# --------------------------------------------------------------------------- #
# NFQUEUE thread                                                                #
# --------------------------------------------------------------------------- #
def nfqueue_thread(fw: Redwall) -> None:
    from netfilterqueue import NetfilterQueue

    cache: dict[tuple, tuple] = {}  # (proto,sport) -> (exe,name,pid), short TTL

    def cb(pkt):
        parsed = parse_packet(pkt.get_payload())
        if not parsed:
            pkt.accept()
            return
        proto, saddr, sport, daddr, dport = parsed
        # DNS fast path: with no deny rules there is nothing to block on :53,
        # so skip attribution and keep resolution cheap.
        if dport == 53 and not fw.rules.has_deny():
            pkt.accept()
            return
        key = (proto, sport)
        now = time.time()
        hit = cache.get(key)
        if hit and now - hit[1] < 5:
            attr = hit[0]
        else:
            attr = attribute(proto, sport)
            cache[key] = (attr, now)
        if not attr:
            pkt.accept()  # kernel/unattributable socket: don't break the system
            return
        exe, name, pid = attr
        fw.handle(pkt, {"exe": exe, "name": name, "dst": daddr,
                        "port": dport, "proto": proto, "pid": pid})

    nfq = NetfilterQueue()
    nfq.bind(QUEUE_NUM, cb, max_len=4096)
    try:
        nfq.run()
    finally:
        nfq.unbind()


# --------------------------------------------------------------------------- #
def main() -> None:
    global SOCK_PATH, RULES_PATH
    ap = argparse.ArgumentParser()
    ap.add_argument("--simulate", action="store_true",
                    help="no NFQUEUE/root; inject synthetic events for UI testing")
    ap.add_argument("--sock", default=SOCK_PATH)
    ap.add_argument("--rules", default=RULES_PATH)
    ap.add_argument("--ui-gid", type=int, default=1000,
                    help="gid allowed to talk to the UI socket")
    args = ap.parse_args()
    SOCK_PATH, RULES_PATH = args.sock, args.rules

    fw = Redwall(Rules(args.rules), args.simulate, args.ui_gid, str(Path(args.rules).parent / "state.json"))

    if not args.simulate:
        threading.Thread(target=nfqueue_thread, args=(fw,), daemon=True).start()

    async def _run():
        tasks = [asyncio.create_task(fw.run_server())]
        if args.simulate:
            tasks.append(asyncio.create_task(fw._sim_seed()))
        await asyncio.gather(*tasks)

    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
