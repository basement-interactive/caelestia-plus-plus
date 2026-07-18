"""redproxy - mitmproxy addon backing the HTTP Debugger tab.

Runs inside `mitmdump` (started on demand by the shell, as the user — no root,
no systemd). Streams every flow to the Quickshell UI over a Unix socket and
takes commands back: toggle intercept, resume/modify/block a held request,
replay a flow, fetch full detail. Same newline-JSON contract as the other
guards.

Socket path comes from $REDPROXY_SOCK. It lives in the per-user runtime dir, so
there is no cross-user concern (unlike the root daemons) and no peer-cred check.

Intercept holds REQUESTS only (edit/allow/block before they go out), which is
what "intercept" means for a debugger; responses stream through untouched.
Fails open: with no UI connected nothing is held, so enabling intercept and
then closing the shell never wedges traffic.
"""
from __future__ import annotations

import asyncio
import json
import os

from mitmproxy import ctx, http

SOCK = os.environ.get("REDPROXY_SOCK") or f"{os.environ.get('XDG_RUNTIME_DIR', '/tmp')}/redproxy.sock"
# When intercepting selected apps mitmdump runs as root (eBPF local mode); the
# socket must then be reachable by the user's shell.
SOCK_GID = int(os.environ.get("REDPROXY_GID") or -1)
MAX_BODY = 256 * 1024  # cap bodies streamed to the UI


class Redproxy:
    def __init__(self) -> None:
        self.clients: set[asyncio.StreamWriter] = set()
        self.flows: dict[str, http.HTTPFlow] = {}   # id -> flow (detail/replay)
        self.held: dict[str, http.HTTPFlow] = {}     # id -> intercepted, awaiting verdict
        self.intercept = False
        self.loop: asyncio.AbstractEventLoop | None = None

    # -- lifecycle ---------------------------------------------------------- #
    def running(self) -> None:
        self.loop = asyncio.get_running_loop()
        asyncio.ensure_future(self._serve())

    # -- mitmproxy hooks ---------------------------------------------------- #
    def request(self, flow: http.HTTPFlow) -> None:
        self.flows[flow.id] = flow
        self._broadcast({"t": "flow", **self._summary(flow)})
        if self.intercept and self.clients:
            flow.intercept()
            self.held[flow.id] = flow
            self._broadcast({"t": "held", **self._summary(flow)})

    def response(self, flow: http.HTTPFlow) -> None:
        self.flows[flow.id] = flow
        self._broadcast({"t": "flowdone", **self._summary(flow)})

    def error(self, flow: http.HTTPFlow) -> None:
        self.held.pop(flow.id, None)
        self._broadcast({"t": "flowerror", "id": flow.id})

    # -- serialisation ------------------------------------------------------ #
    def _summary(self, flow: http.HTTPFlow) -> dict:
        r = flow.request
        resp = flow.response
        ms = 0
        if resp and resp.timestamp_end and r.timestamp_start:
            ms = int((resp.timestamp_end - r.timestamp_start) * 1000)
        return {
            "id": flow.id,
            "method": r.method,
            "url": r.pretty_url,
            "host": r.pretty_host,
            "scheme": r.scheme,
            "status": resp.status_code if resp else 0,
            "size": len(resp.raw_content) if resp and resp.raw_content else 0,
            "ctype": (resp.headers.get("content-type", "").split(";")[0] if resp else ""),
            "ms": ms,
            "held": flow.id in self.held,
        }

    @staticmethod
    def _body(msg) -> dict:
        raw = msg.content if msg else None
        if not raw:
            return {"text": "", "truncated": False, "binary": False}
        truncated = len(raw) > MAX_BODY
        chunk = raw[:MAX_BODY]
        try:
            return {"text": chunk.decode("utf-8"), "truncated": truncated, "binary": False}
        except UnicodeDecodeError:
            return {"text": f"[{len(raw)} bytes of binary data]", "truncated": False, "binary": True}

    def _detail(self, flow: http.HTTPFlow) -> dict:
        def hdrs(m):
            return [[k, v] for k, v in m.items(multi=True)]
        d = {
            "t": "detail",
            "id": flow.id,
            "reqHeaders": hdrs(flow.request.headers),
            "reqBody": self._body(flow.request),
            "respHeaders": [],
            "respBody": {"text": "", "truncated": False, "binary": False},
        }
        if flow.response:
            d["respHeaders"] = hdrs(flow.response.headers)
            d["respBody"] = self._body(flow.response)
        return d

    # -- UI messaging ------------------------------------------------------- #
    def _broadcast(self, msg: dict) -> None:
        data = (json.dumps(msg) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(data)
            except Exception:
                self.clients.discard(w)

    # -- commands from the UI ---------------------------------------------- #
    def _apply_mods(self, flow: http.HTTPFlow, msg: dict) -> None:
        r = flow.request
        if msg.get("method"):
            r.method = msg["method"]
        if msg.get("url"):
            try:
                r.url = msg["url"]
            except ValueError:
                pass
        if isinstance(msg.get("headers"), list):
            r.headers.clear()
            for pair in msg["headers"]:
                if len(pair) == 2 and pair[0]:
                    r.headers.add(pair[0], pair[1])
        if "body" in msg and msg["body"] is not None:
            r.content = msg["body"].encode("utf-8")

    def _on_message(self, msg: dict) -> None:
        t = msg.get("t")
        if t == "intercept":
            self.intercept = bool(msg.get("on"))
            if not self.intercept:
                for fid in list(self.held):
                    self._release(fid)
            self._broadcast({"t": "state", "intercept": self.intercept})
        elif t == "resume":
            flow = self.held.get(msg.get("id"))
            if flow:
                self._apply_mods(flow, msg)
                self._release(msg["id"])
        elif t == "block":
            flow = self.held.pop(msg.get("id"), None)
            if flow:
                if flow.killable:
                    flow.kill()
                self._broadcast({"t": "resolved", "id": msg["id"]})
        elif t == "replay":
            flow = self.flows.get(msg.get("id"))
            if flow:
                ctx.master.commands.call("replay.client", [flow.copy()])
        elif t == "getdetail":
            flow = self.flows.get(msg.get("id"))
            if flow:
                self._broadcast(self._detail(flow))
        elif t == "clear":
            self.flows = {k: v for k, v in self.flows.items() if k in self.held}
            self._broadcast({"t": "cleared"})
        elif t == "setlocal":
            # Change which apps eBPF local mode captures, live — no restart, so
            # no repeated privilege prompt. Runtime mode updates reconfigure the
            # proxy servers in place.
            apps = msg.get("apps") or []
            port = os.environ.get("REDPROXY_PORT", "8081")
            modes = [f"regular@{port}"]
            if apps:
                modes.append("local:" + ",".join(apps))
            ctx.options.update(mode=modes)
        elif t == "shutdown":
            # Clean self-exit. Used to stop a root (local-mode) mitmdump, which
            # the unprivileged shell cannot signal (setuid child).
            ctx.master.shutdown()

    def _release(self, fid: str) -> None:
        flow = self.held.pop(fid, None)
        if flow:
            if flow.intercepted:
                flow.resume()
            self._broadcast({"t": "resolved", "id": fid})

    # -- socket server ------------------------------------------------------ #
    async def _serve(self) -> None:
        try:
            os.unlink(SOCK)
        except FileNotFoundError:
            pass
        server = await asyncio.start_unix_server(self._client, path=SOCK)
        if SOCK_GID >= 0:
            try:
                os.chown(SOCK, 0, SOCK_GID)
                os.chmod(SOCK, 0o660)
            except OSError:
                os.chmod(SOCK, 0o600)
        else:
            os.chmod(SOCK, 0o600)
        async with server:
            await server.serve_forever()

    async def _client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.clients.add(writer)
        writer.write((json.dumps({"t": "state", "intercept": self.intercept,
                                  "port": ctx.options.listen_port}) + "\n").encode())
        for flow in self.held.values():
            writer.write((json.dumps({"t": "held", **self._summary(flow)}) + "\n").encode())
        try:
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break
                try:
                    self._on_message(json.loads(line))
                except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
                    ctx.log.warn(f"[redproxy] bad message: {e}")
        except (ConnectionError, OSError):
            pass
        finally:
            self.clients.discard(writer)
            try:
                writer.close()
            except Exception:
                pass


addons = [Redproxy()]
