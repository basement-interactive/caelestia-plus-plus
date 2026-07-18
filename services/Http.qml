pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

// Backend for the HTTP Debugger tab. Runs mitmdump on demand (as the user, no
// root, no systemd — it's a debugging proxy, not an always-on service) with the
// redproxy addon, and bridges its control socket: live flow list, intercept,
// resume/modify, block, replay, detail. HTTPS needs mitmproxy's CA trusted
// (one pkexec step). VPN-safe: it's an explicit localhost proxy, so the tunnel
// still carries mitmdump's own outbound.
Singleton {
    id: root

    readonly property int port: 8081
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/redproxy.sock`
    readonly property string caCert: `${Paths.home}/.mitmproxy/mitmproxy-ca-cert.pem`

    // proxy lifecycle
    property bool running: proc.running
    readonly property bool connected: sockLoader.item?.connected ?? false
    property bool intercept: false

    // environment
    property bool installed: false        // mitmdump present
    property bool caTrusted: false        // CA in the system trust store
    property bool systemProxy: false      // gsettings proxy pointed at us

    // Per-app capture via mitmproxy's eBPF local mode. Needs the redirector
    // helper to hold caps; one-time setcap (localReady) then it runs as us.
    property string redirectorPath: ""
    property bool localReady: false       // redirector has the eBPF caps
    property var runningApps: []          // [{cls, pid, comm, title}]
    property var selectedApps: []         // process names for the local spec

    // Newest-first capped flow list + the currently open flow's detail.
    property var flows: []
    property var detail: null
    readonly property int heldCount: flows.filter(f => f.held).length
    readonly property int maxFlows: 300

    // local mode only once the redirector is capability-granted, so selecting
    // an app before the one-time setup never triggers mitmproxy's own polkit
    // prompt (which would appear behind this overlay panel).
    readonly property bool localActive: localReady && selectedApps.length > 0

    function _command(): var {
        const modes = ["--mode", `regular@${root.port}`];
        if (root.localActive)
            modes.push("--mode", `local:${root.selectedApps.join(",")}`);
        return ["mitmdump", "-q", "--listen-host", "127.0.0.1", "-s",
            Quickshell.shellPath("system/redproxy/addon.py")].concat(modes);
    }

    function start(): void {
        if (proc.running)
            return;
        flows = [];
        detail = null;
        proc.command = _command();
        proc.running = true;
    }

    // Changing which apps are captured means relaunching mitmdump (modes are
    // fixed at start). Only relaunch when local mode is actually usable —
    // otherwise the selection just arms the "Enable" prompt.
    function setSelectedApps(names: var): void {
        const wasActive = root.localActive;
        root.selectedApps = names;
        if (proc.running && (root.localActive || wasActive)) {
            proc.running = false;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 400
        onTriggered: root.start()
    }

    function enumerateApps(): void {
        appEnum.running = true;
    }

    function stop(): void {
        proc.running = false;
        if (systemProxy)
            setSystemProxy(false);
    }

    function toggle(): void {
        proc.running ? stop() : start();
    }

    function _send(obj: var): void {
        if (sockLoader.item?.connected)
            sockLoader.item.write(JSON.stringify(obj) + "\n");
    }

    function setIntercept(on: bool): void {
        root.intercept = on;
        _send({t: "intercept", on: on});
    }

    // mods: {method?, url?, headers?: [[k,v]], body?} — all optional
    function resume(id: string, mods: var): void {
        _send(Object.assign({t: "resume", id: id}, mods ?? {}));
    }
    function block(id: string): void { _send({t: "block", id: id}); }
    function replay(id: string): void { _send({t: "replay", id: id}); }
    function requestDetail(id: string): void {
        root.detail = null;
        _send({t: "getdetail", id: id});
    }
    function clear(): void {
        flows = [];
        _send({t: "clear"});
    }

    function _upsert(msg: var, done: bool): void {
        const list = root.flows.slice();
        const i = list.findIndex(f => f.id === msg.id);
        if (i >= 0)
            list[i] = Object.assign({}, list[i], msg);
        else
            list.unshift(msg);
        if (list.length > root.maxFlows)
            list.length = root.maxFlows;
        root.flows = list;
    }

    function _mark(id: string, held: bool): void {
        const list = root.flows.slice();
        const i = list.findIndex(f => f.id === id);
        if (i >= 0) {
            list[i] = Object.assign({}, list[i], {held: held});
            root.flows = list;
        }
    }

    function _handle(line: string): void {
        if (!line)
            return;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.t) {
        case "flow":
        case "held":
            _upsert(msg, false);
            break;
        case "flowdone":
            _upsert(msg, true);
            break;
        case "resolved":
            _mark(msg.id, false);
            break;
        case "flowerror":
            _mark(msg.id, false);
            break;
        case "detail":
            root.detail = msg;
            break;
        case "state":
            root.intercept = msg.intercept ?? false;
            break;
        case "cleared":
            break;
        }
    }

    // mitmdump child process. Inherits the session env (merged), plus the
    // control-socket path the addon reads.
    Process {
        id: proc

        command: root._command()  // replaced per-start with the current modes
        environment: ({
                REDPROXY_SOCK: root.sockPath
            })
        stdout: SplitParser {
            onRead: data => console.info("mitmdump:", data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("mitmdump:", data)
        }
        onExited: code => {
            root.flows = root.flows.map(f => Object.assign({}, f, {held: false}));
            if (code !== 0 && code !== 15) // 15 = SIGTERM on stop()
                Toaster.toast(qsTr("HTTP proxy stopped"), qsTr("mitmdump exited with code %1").arg(code), "warning");
        }
    }

    // Same recreate-on-demand socket the guards use: the addon's socket only
    // exists while the proxy runs, so rebuild until it appears.
    Loader {
        id: sockLoader

        active: root.running
        sourceComponent: Component {
            Socket {
                path: root.sockPath
                connected: true

                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: line => root._handle(line)
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: root.running && !root.connected
        repeat: true
        onTriggered: {
            sockLoader.active = false;
            reconnectKick.restart();
        }
    }

    Timer {
        id: reconnectKick
        interval: 50
        onTriggered: sockLoader.active = Qt.binding(() => root.running)
    }

    // --- environment probing + setup --------------------------------------- #
    function probe(): void {
        probeProc.running = true;
    }

    Process {
        id: probeProc

        command: ["sh", "-c", `command -v mitmdump >/dev/null && echo inst
[ -e /etc/ca-certificates/trust-source/anchors/mitmproxy.crt ] && echo ca
[ "$(gsettings get org.gnome.system.proxy mode 2>/dev/null)" = "'manual'" ] && echo sysproxy
rp=$(python3 -c 'import mitmproxy_linux; print(mitmproxy_linux.executable_path())' 2>/dev/null)
[ -n "$rp" ] && echo "redir|$rp"
[ -n "$rp" ] && getcap "$rp" 2>/dev/null | grep -qi cap && echo localready
true`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.includes("inst");
                root.caTrusted = text.includes("ca");
                root.systemProxy = text.includes("sysproxy");
                root.localReady = text.includes("localready");
                const m = text.match(/redir\|(.+)/);
                root.redirectorPath = m ? m[1].trim() : "";
            }
        }
    }

    // App picker source: running Hyprland toplevels with their pid → process
    // name (the local-mode spec matches by process name, catching an app's
    // helper processes too).
    Process {
        id: appEnum

        command: ["sh", "-c", `hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    pid = c.get('pid', 0); cls = c.get('class', ''); title = c.get('title', '')
    if pid <= 0 or not cls: continue
    try: comm = open(f'/proc/{pid}/comm').read().strip()
    except OSError: comm = cls
    print('|'.join((cls, str(pid), comm, title[:48])).replace(chr(10), ' '))
"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                const apps = [];
                for (const line of text.trim().split("\n")) {
                    if (!line)
                        continue;
                    const f = line.split("|");
                    if (f.length < 3 || seen.has(f[2]))
                        continue;
                    seen.add(f[2]);
                    apps.push({cls: f[0], pid: parseInt(f[1], 10), comm: f[2], title: f[3] ?? ""});
                }
                root.runningApps = apps;
            }
        }
    }

    // One-time: give the eBPF redirector the caps it needs, so per-app capture
    // then runs as the user with no prompt (instead of a polkit prompt each
    // time mitmproxy would self-elevate).
    function enablePerApp(): void {
        if (!root.redirectorPath)
            return;
        enableProc.running = true;
        Toaster.toast(qsTr("Enabling per-app capture"), qsTr("Enter your password — one-time setup"), "key");
    }

    Process {
        id: enableProc
        command: ["timeout", "120", "pkexec", "setcap", "cap_bpf,cap_net_admin,cap_sys_admin,cap_sys_resource+ep", root.redirectorPath]
        onExited: code => {
            if (code === 0)
                root.localReady = true; // set directly; probe() is async
            root.probe();
            // Apply the pending app selection now that local mode is usable.
            if (code === 0 && proc.running && root.selectedApps.length) {
                proc.running = false;
                restartTimer.restart();
            }
            Toaster.toast(code === 0 ? qsTr("Per-app capture ready") : qsTr("Setup failed"), code === 0 ? qsTr("Routing the selected apps through the proxy") : qsTr("See the debug console"), code === 0 ? "task_alt" : "warning");
        }
    }

    function install(): void {
        installProc.running = true;
        Toaster.toast(qsTr("Installing mitmproxy"), qsTr("Enter your password to install the proxy"), "key");
    }

    Process {
        id: installProc
        command: ["timeout", "600", "pkexec", "pacman", "-S", "--needed", "--noconfirm", "mitmproxy"]
        onExited: code => {
            root.probe();
            Toaster.toast(code === 0 ? qsTr("mitmproxy installed") : qsTr("Install failed"), code === 0 ? qsTr("Start the proxy to begin capturing") : qsTr("See the debug console"), code === 0 ? "task_alt" : "warning");
        }
    }

    // Trust the CA (system-wide) so HTTPS flows decrypt. The CA is generated on
    // the proxy's first run, so this is only offered once the cert exists.
    function trustCa(): void {
        trustProc.running = true;
        Toaster.toast(qsTr("Trusting mitmproxy CA"), qsTr("Enter your password — HTTPS flows will decrypt after this"), "key");
    }

    Process {
        id: trustProc
        command: ["timeout", "120", "pkexec", "sh", "-c", `install -Dm644 '${root.caCert}' /etc/ca-certificates/trust-source/anchors/mitmproxy.crt && update-ca-trust`]
        onExited: code => {
            root.probe();
            Toaster.toast(code === 0 ? qsTr("CA trusted") : qsTr("Could not trust CA"), code === 0 ? qsTr("HTTPS traffic through the proxy now decrypts") : qsTr("Run the proxy once first, then retry"), code === 0 ? "verified" : "warning");
        }
    }

    // Point GTK/GNOME-family apps at the proxy for the session. Others accept
    // the address manually (shown in the tab). Localhost proxy, so VPN-safe.
    function setSystemProxy(on: bool): void {
        root.systemProxy = on;
        if (on)
            Quickshell.execDetached(["sh", "-c", `gsettings set org.gnome.system.proxy mode 'manual'; gsettings set org.gnome.system.proxy.http host '127.0.0.1'; gsettings set org.gnome.system.proxy.http port ${root.port}; gsettings set org.gnome.system.proxy.https host '127.0.0.1'; gsettings set org.gnome.system.proxy.https port ${root.port}; gsettings set org.gnome.system.proxy ignore-hosts "['localhost','127.0.0.0/8','::1']"`]);
        else
            Quickshell.execDetached(["gsettings", "set", "org.gnome.system.proxy", "mode", "none"]);
    }

    Component.onCompleted: probe()

    IpcHandler {
        target: "http"

        function toggle(): void { root.toggle(); }
        function status(): string {
            return root.running ? `running :${root.port}; ${root.flows.length} flows; intercept ${root.intercept ? "on" : "off"}` : "stopped";
        }
    }
}
