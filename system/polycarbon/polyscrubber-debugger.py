#!/usr/bin/env python3
"""Polyscrubber debugger — the memory-editing frontend.

Opened from the polyscrubber overlay ("debugger" action) for the attached
Polycarbon app. This is the unprivileged UI half; it launches the engine
(polyscrubber-engine) with pkexec so it can read the target's memory under
ptrace_scope=1, then drives it over a line-JSON pipe.

Layout is three tabs, ImGui-dark to match the overlay:
  · Scan   — typed value scan, refine (next-scan), result list, edit/freeze
  · Memory — hex+ASCII viewer/editor at any address, byte/string patching
  · Engine — detected game engine, module list, region map (the explorer)

Everything that touches memory lives in the engine; this file is UI plus
the pipe. It never needs privilege itself.
"""
import json
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import GLib, GObject, Gdk, Gtk, Pango  # noqa: E402

ENGINE = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                      "polyscrubber-engine")
VALUE_TYPES = ["i32", "u32", "i64", "u64", "f32", "f64",
               "i8", "u8", "i16", "u16", "string", "bytes"]

CSS = b"""
window, .imgui { background: rgba(15,15,15,0.98); color: #fff;
                 font: 10pt monospace; }
notebook header { background: rgb(20,20,20); }
notebook tab { background: rgb(30,30,30); padding: 4px 12px; }
notebook tab:checked { background: rgb(41,74,122); }
entry, treeview, textview, textview text {
    background: rgb(24,24,24); color: #eee; border-radius: 0; }
button { background: rgba(66,150,250,0.40);
         border: 1px solid rgba(110,110,128,0.5);
         padding: 3px 10px; border-radius: 0; }
button:hover { background: rgba(66,150,250,0.65); }
.status { color: #9a9a9a; padding: 3px 6px; }
.mono { font-family: monospace; }
.sig { color: rgb(120,200,120); }
"""


class Engine:
    """The privileged memory engine, spoken to over a JSON-line pipe."""

    def __init__(self, pid):
        # The engine runs itself (its shebang), so pkexec's prompt names the
        # real engine path — not a bare "python3" that would over-authorise
        cmd = ["pkexec", ENGINE]
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1)
        self.pid = pid

    def call(self, **kw):
        try:
            self.proc.stdin.write(json.dumps(kw) + "\n")
            self.proc.stdin.flush()
            line = self.proc.stdout.readline()
            return json.loads(line) if line else {"ok": False,
                                                  "error": "engine closed"}
        except (BrokenPipeError, ValueError) as e:
            return {"ok": False, "error": str(e)}

    def alive(self):
        return self.proc.poll() is None

    def close(self):
        try:
            self.proc.terminate()
        except OSError:
            pass


def fmt_addr(a):
    return f"0x{a:012x}"


class Debugger(Gtk.Window):
    def __init__(self, pid, app_name):
        super().__init__(title=f"polyscrubber debugger — {app_name}")
        self.set_default_size(760, 560)
        self.get_style_context().add_class("imgui")
        self.engine = Engine(pid)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)
        self.tabs = Gtk.Notebook()
        outer.pack_start(self.tabs, True, True, 0)
        self.status = Gtk.Label(xalign=0, label="attaching…")
        self.status.get_style_context().add_class("status")
        outer.pack_start(self.status, False, False, 0)

        self.tabs.append_page(self.build_scan(), Gtk.Label(label="Scan"))
        self.tabs.append_page(self.build_memory(), Gtk.Label(label="Memory"))
        self.tabs.append_page(self.build_engine(), Gtk.Label(label="Engine"))

        self.connect("destroy", self.on_destroy)
        GLib.idle_add(self.attach)

    def set_status(self, text):
        self.status.set_text(text)

    def attach(self):
        r = self.engine.call(op="attach", pid=self.engine.pid)
        if not r.get("ok"):
            self.set_status(f"attach failed: {r.get('error')}")
            return
        self.render_detect(r["detect"])
        self.set_status(f"attached to pid {self.engine.pid} — "
                        f"engine: {r['detect']['engine']}")

    # --- Scan tab ---------------------------------------------------------

    def build_scan(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(8)

        controls = Gtk.Box(spacing=6)
        self.scan_value = Gtk.Entry(placeholder_text="value to find")
        self.scan_value.connect("activate", self.on_scan)
        self.scan_type = Gtk.ComboBoxText()
        for t in VALUE_TYPES:
            self.scan_type.append_text(t)
        self.scan_type.set_active(0)
        first = Gtk.Button(label="First scan")
        first.connect("clicked", self.on_scan)
        nxt = Gtk.Button(label="Next: =")
        nxt.connect("clicked", lambda _b: self.on_refine("eq"))
        gt = Gtk.Button(label=">")
        gt.connect("clicked", lambda _b: self.on_refine("gt"))
        lt = Gtk.Button(label="<")
        lt.connect("clicked", lambda _b: self.on_refine("lt"))
        for w in (self.scan_value, self.scan_type, first, nxt, gt, lt):
            controls.pack_start(w, False, False, 0)
        box.pack_start(controls, False, False, 0)

        # addr | value  result list
        self.results = Gtk.ListStore(str, str, GObject.TYPE_INT64)
        view = Gtk.TreeView(model=self.results)
        for i, title in enumerate(("address", "value")):
            view.append_column(
                Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=i))
        view.connect("row-activated", self.on_result_activated)
        self.results_view = view
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)

        act = Gtk.Box(spacing=6)
        self.edit_value = Gtk.Entry(placeholder_text="new value for selection")
        setb = Gtk.Button(label="Set")
        setb.connect("clicked", self.on_set_selected)
        frz = Gtk.Button(label="Freeze")
        frz.connect("clicked", self.on_freeze_selected)
        unfrz = Gtk.Button(label="Unfreeze")
        unfrz.connect("clicked", self.on_unfreeze_selected)
        for w in (self.edit_value, setb, frz, unfrz):
            act.pack_start(w, False, False, 0)
        box.pack_start(act, False, False, 0)
        return box

    def on_scan(self, _w):
        val = self.scan_value.get_text().strip()
        vtype = self.scan_type.get_active_text()
        if not val:
            return
        self.set_status("scanning…")
        r = self.engine.call(op="scan", type=vtype, value=val)
        self.fill_results(r)
        note = " (truncated)" if r.get("truncated") else ""
        self.set_status(f"{r.get('count', 0)} matches{note}")

    def on_refine(self, cmp):
        vtype = self.scan_type.get_active_text()
        val = self.scan_value.get_text().strip()
        kw = {"op": "refine", "cmp": cmp}
        if cmp in ("eq", "ne", "gt", "lt"):
            kw["value"] = val
        r = self.engine.call(**kw)
        self.fill_results(r)
        self.set_status(f"{r.get('count', 0)} matches after refine")

    def fill_results(self, r):
        self.results.clear()
        for m in r.get("sample", []):
            self.results.append([fmt_addr(m["addr"]), str(m["value"]),
                                 m["addr"]])

    def _selected_addr(self):
        model, it = self.results_view.get_selection().get_selected()
        return model[it][2] if it else None

    def on_result_activated(self, view, path, _col):
        addr = self.results[path][2]
        self.mem_addr.set_text(fmt_addr(addr))
        self.tabs.set_current_page(1)
        self.refresh_hex()

    def on_set_selected(self, _b):
        addr = self._selected_addr()
        if addr is None:
            return
        r = self.engine.call(op="write", type=self.scan_type.get_active_text(),
                             value=self.edit_value.get_text().strip(),
                             addr=addr)
        self.set_status("wrote" if r.get("ok") else f"write failed: {r.get('error')}")

    def on_freeze_selected(self, _b):
        addr = self._selected_addr()
        if addr is None:
            return
        r = self.engine.call(op="freeze", type=self.scan_type.get_active_text(),
                             value=self.edit_value.get_text().strip() or "0",
                             addr=addr)
        self.set_status(f"frozen ({r.get('frozen')} total)")

    def on_unfreeze_selected(self, _b):
        addr = self._selected_addr()
        if addr is None:
            return
        self.engine.call(op="unfreeze", addr=addr)
        self.set_status("unfrozen")

    # --- Memory tab (hex editor) ------------------------------------------

    def build_memory(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(8)

        nav = Gtk.Box(spacing=6)
        self.mem_addr = Gtk.Entry(placeholder_text="0x… address")
        self.mem_addr.connect("activate", lambda _e: self.refresh_hex())
        go = Gtk.Button(label="Go")
        go.connect("clicked", lambda _b: self.refresh_hex())
        self.mem_len = Gtk.SpinButton.new_with_range(16, 4096, 16)
        self.mem_len.set_value(256)
        self.mem_len.connect("value-changed", lambda _s: self.refresh_hex())
        for w in (Gtk.Label(label="addr"), self.mem_addr,
                  Gtk.Label(label="len"), self.mem_len, go):
            nav.pack_start(w, False, False, 0)
        box.pack_start(nav, False, False, 0)

        self.hex_view = Gtk.TextView(editable=False, monospace=True)
        self.hex_view.override_font(Pango.FontDescription("monospace 10"))
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.hex_view)
        box.pack_start(scroll, True, True, 0)

        patch = Gtk.Box(spacing=6)
        self.patch_addr = Gtk.Entry(placeholder_text="0x… address")
        self.patch_type = Gtk.ComboBoxText()
        for t in VALUE_TYPES:
            self.patch_type.append_text(t)
        self.patch_type.set_active(VALUE_TYPES.index("bytes"))
        self.patch_value = Gtk.Entry(placeholder_text="hex bytes / value")
        pb = Gtk.Button(label="Overwrite")
        pb.connect("clicked", self.on_patch)
        for w in (Gtk.Label(label="write"), self.patch_addr, self.patch_type,
                  self.patch_value, pb):
            patch.pack_start(w, False, False, 0)
        box.pack_start(patch, False, False, 0)
        return box

    def refresh_hex(self):
        try:
            addr = int(self.mem_addr.get_text().strip(), 16)
        except ValueError:
            self.set_status("memory: address must be hex (0x…)")
            return
        length = int(self.mem_len.get_value())
        r = self.engine.call(op="read", size=length, addr=addr)
        if not r.get("ok") or not r.get("hex"):
            self.hex_view.get_buffer().set_text("(unreadable)")
            return
        raw = bytes.fromhex(r["hex"])
        self.hex_view.get_buffer().set_text(hexdump(raw, addr))

    def on_patch(self, _b):
        try:
            addr = int(self.patch_addr.get_text().strip(), 16)
        except ValueError:
            self.set_status("write: address must be hex (0x…)")
            return
        r = self.engine.call(op="write", type=self.patch_type.get_active_text(),
                             value=self.patch_value.get_text().strip(),
                             addr=addr)
        self.set_status(f"wrote {r.get('wrote')} bytes" if r.get("ok")
                        else f"write failed: {r.get('error')}")
        self.refresh_hex()

    # --- Engine tab (the explorer) ----------------------------------------

    def build_engine(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(8)
        self.detect_label = Gtk.Label(xalign=0, label="detecting…")
        self.detect_label.set_line_wrap(True)
        box.pack_start(self.detect_label, False, False, 0)

        self.mod_store = Gtk.ListStore(str, str)  # base, path
        view = Gtk.TreeView(model=self.mod_store)
        view.append_column(Gtk.TreeViewColumn("base", Gtk.CellRendererText(),
                                              text=0))
        view.append_column(Gtk.TreeViewColumn("module", Gtk.CellRendererText(),
                                              text=1))
        view.connect("row-activated", self.on_module_activated)
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)
        refresh = Gtk.Button(label="Refresh modules")
        refresh.connect("clicked", lambda _b: self.load_modules())
        box.pack_start(refresh, False, False, 0)
        return box

    def render_detect(self, d):
        parts = [f"<b>engine:</b> <span class='sig'>{d['engine']}</span>"]
        if d.get("runtime"):
            parts.append(f"<b>runtime:</b> {d['runtime']}")
        if d.get("renderer"):
            parts.append(f"<b>renderer:</b> {d['renderer']}")
        parts.append(f"<b>modules:</b> {d['module_count']}")
        if d.get("signatures"):
            parts.append("<b>matched:</b> " + ", ".join(d["signatures"]))
        self.detect_label.set_markup("   ".join(parts))
        self.load_modules()

    def load_modules(self):
        r = self.engine.call(op="modules")
        self.mod_store.clear()
        for m in r.get("modules", []):
            self.mod_store.append([fmt_addr(m["base"]),
                                   m["path"].rsplit("/", 1)[-1]])

    def on_module_activated(self, view, path, _col):
        base = int(self.mod_store[path][0], 16)
        self.mem_addr.set_text(fmt_addr(base))
        self.tabs.set_current_page(1)
        self.refresh_hex()

    def on_destroy(self, _w):
        self.engine.close()
        Gtk.main_quit()


def hexdump(raw, base):
    lines = []
    for off in range(0, len(raw), 16):
        chunk = raw[off:off + 16]
        hexpart = " ".join(f"{b:02x}" for b in chunk).ljust(47)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{base + off:012x}  {hexpart}  {asc}")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("usage: polyscrubber-debugger <pid> [app-name]", file=sys.stderr)
        return 2
    pid = int(sys.argv[1])
    name = sys.argv[2] if len(sys.argv) > 2 else str(pid)

    style = Gtk.CssProvider()
    style.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), style,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    win = Debugger(pid, name)
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
