pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

// System health scanner behind the debug window's "System scan" tab. Probes
// everything the shell needs to run at full function — runtime binaries, the
// power-profiles daemon, the root-half feature installers, pending shell
// updates — and attaches a one-click fix to each finding. Everything that
// needs root (package installs, systemctl, the feature installers, pacman
// config) goes through pkexec, so the user only ever types a password.
//
// A scan also runs once at startup: if it finds missing packages that were
// not dismissed before, SetupPrompt (modules/debug) shows a centered offer
// to install them.
Singleton {
    id: root

    property bool scanning
    property string lastScan
    property string busyId

    // [{id, name, detail, status: ok|warn|fail|info, fixType, fixData, fixLabel}]
    property var results: []
    readonly property int problemCount: results.filter(r => r.status === "warn" || r.status === "fail").length
    readonly property var missingPackages: results.filter(r => r.fixType === "install").map(r => r.fixData)

    // Rows that warrant the unprompted startup dialog: missing packages and
    // outdated (already installed) privileged halves
    readonly property var promptItems: results.filter(r => r.prompt)
    readonly property var outdatedRootHalves: results.filter(r => r.fixType === "roothalf" && r.prompt).map(r => r.fixData)

    property bool promptOpen: false
    readonly property string statePath: `${Paths.state}/systemcheck.json`
    property var dismissedPackages: []
    property var dismissedRootHalves: ({})
    property var _verState: ({})

    // Runtime tools the shell calls, with the Arch package that provides
    // them and what breaks without them
    readonly property var binaries: [
        {bin: "wl-copy", pkg: "wl-clipboard", why: qsTr("Clipboard: screenshots, colour picker, console copy"), severity: "fail"},
        {bin: "nmcli", pkg: "networkmanager", why: qsTr("Network status and wifi connections in the bar"), severity: "fail"},
        {bin: "python3", pkg: "python", why: qsTr("Shell helper scripts"), severity: "fail"},
        {bin: "notify-send", pkg: "libnotify", why: qsTr("Desktop notifications from shell actions"), severity: "warn"},
        {bin: "powerprofilesctl", pkg: "power-profiles-daemon", why: qsTr("Power profile switching (battery popout, bed mode)"), severity: "warn"},
        {bin: "ddcutil", pkg: "ddcutil", why: qsTr("Brightness control for external monitors"), severity: "warn"},
        {bin: "brightnessctl", pkg: "brightnessctl", why: qsTr("Brightness control for the internal display"), severity: "warn", laptopOnly: true},
        {bin: "gpu-screen-recorder", pkg: "gpu-screen-recorder", why: qsTr("Screen recording from the utilities drawer"), severity: "warn"},
        {bin: "swappy", pkg: "swappy", why: qsTr("Screenshot annotation"), severity: "warn"},
        {bin: "xmllint", pkg: "libxml2", why: qsTr("Weather and metadata parsing"), severity: "warn"}
    ]

    function scan(): void {
        if (scanning)
            return;
        scanning = true;
        ShellUpdates.check();
        const bins = binaries.map(b => b.bin).join(" ");
        probe.command = ["sh", "-c", `for b in ${bins}; do command -v "$b" >/dev/null 2>&1 && echo "bin|$b|ok" || echo "bin|$b|missing"; done
systemctl is-active -q power-profiles-daemon 2>/dev/null && echo "ppd|active" || echo "ppd|inactive"
[ -f "$HOME/.face" ] && echo "face|ok" || echo "face|missing"
grep -qs 'IgnorePkg.*caelestia' /etc/pacman.conf && echo "ignpkg|ok" || echo "ignpkg|missing"
for f in max-perf anti-heat dynamic bed-mode; do
  repo=$(grep -m1 '^root_half_version=' "${Quickshell.shellDir}/system/$f/install.sh" 2>/dev/null | cut -d= -f2)
  [ -n "$repo" ] || repo=0
  inst=$(cat "/etc/caelestia/$f.version" 2>/dev/null || echo 0)
  if systemctl is-enabled -q "$f-sync.path" 2>/dev/null; then en=1; else en=0; fi
  echo "ver|$f|$repo|$inst|$en"
done`];
        probe.running = true;
    }

    function runFix(id: string): void {
        const r = results.find(x => x.id === id);
        if (!r || busyId)
            return;
        switch (r.fixType) {
        case "install":
            busyId = id;
            fixProc.command = ["pkexec", "pacman", "-S", "--needed", "--noconfirm", r.fixData];
            fixProc.running = true;
            break;
        case "daemon":
            busyId = id;
            fixProc.command = ["pkexec", "systemctl", "enable", "--now", "power-profiles-daemon"];
            fixProc.running = true;
            break;
        case "update":
            ShellUpdates.update();
            break;
        case "roothalf":
            busyId = id;
            fixProc.command = ["pkexec", "bash", `${Quickshell.shellDir}/system/${r.fixData}/install.sh`];
            fixProc.running = true;
            break;
        case "ignorepkg":
            busyId = id;
            fixProc.command = ["pkexec", "sh", "-c", "printf 'IgnorePkg = caelestia++-shell caelestia++-cli\\n' >> /etc/pacman.conf"];
            fixProc.running = true;
            break;
        }
    }

    function installAllMissing(): void {
        if (!missingPackages.length || busyId)
            return;
        busyId = "all";
        fixProc.command = ["pkexec", "pacman", "-S", "--needed", "--noconfirm"].concat(missingPackages);
        fixProc.running = true;
    }

    // Everything the startup prompt covers in a single pkexec (one password):
    // missing packages, then each outdated privileged half's installer
    function fixAllPrompted(): void {
        if (busyId)
            return;
        const cmds = [];
        if (missingPackages.length)
            cmds.push("pacman -S --needed --noconfirm " + missingPackages.join(" "));
        for (const dir of outdatedRootHalves)
            cmds.push(`bash '${Quickshell.shellDir}/system/${dir}/install.sh'`);
        if (!cmds.length)
            return;
        busyId = "all";
        fixProc.command = ["pkexec", "sh", "-c", cmds.join(" && ")];
        fixProc.running = true;
    }

    function dismissPrompt(): void {
        dismissedPackages = [...new Set(dismissedPackages.concat(missingPackages))];
        const halves = Object.assign({}, dismissedRootHalves);
        for (const dir of outdatedRootHalves)
            halves[dir] = _verState[dir]?.repo ?? 0;
        dismissedRootHalves = halves;
        store.setText(JSON.stringify({dismissedPackages: dismissedPackages, dismissedRootHalves: dismissedRootHalves}, null, 2) + "\n");
        promptOpen = false;
    }

    function _finish(out: string): void {
        const flags = {};
        const vers = {};
        for (const line of out.trim().split("\n")) {
            const parts = line.split("|");
            if (parts[0] === "ver")
                vers[parts[1]] = {repo: parseInt(parts[2], 10) || 0, inst: parseInt(parts[3], 10) || 0, enabled: parts[4] === "1"};
            else
                flags[parts.length === 3 ? `${parts[0]}.${parts[1]}` : parts[0]] = parts[parts.length - 1];
        }
        _verState = vers;

        const rows = [];

        for (const b of binaries) {
            if (b.laptopOnly && !SysInfo.isLaptop)
                continue;
            const ok = flags[`bin.${b.bin}`] === "ok";
            rows.push({
                id: `bin-${b.bin}`,
                name: ok ? qsTr("%1 installed").arg(b.pkg) : qsTr("%1 missing").arg(b.pkg),
                detail: b.why,
                status: ok ? "ok" : b.severity,
                fixType: ok ? "none" : "install",
                fixData: b.pkg,
                fixLabel: ok ? "" : qsTr("Install"),
                prompt: !ok
            });
        }

        if (flags["bin.powerprofilesctl"] === "ok") {
            const active = flags.ppd === "active";
            rows.push({
                id: "ppd-service",
                name: active ? qsTr("power-profiles-daemon running") : qsTr("power-profiles-daemon not running"),
                detail: qsTr("The daemon behind power profile switching"),
                status: active ? "ok" : "warn",
                fixType: active ? "none" : "daemon",
                fixData: "",
                fixLabel: active ? "" : qsTr("Enable")
            });
        }

        rows.push({
            id: "shell-updates",
            name: ShellUpdates.updateAvailable ? qsTr("Shell %1 commits behind").arg(ShellUpdates.commitsBehind) : qsTr("Shell up to date"),
            detail: ShellUpdates.updateAvailable ? qsTr("Newer Caelestia++ is on origin/main") : qsTr("Checked against origin/main"),
            status: ShellUpdates.updateAvailable ? "warn" : "ok",
            fixType: ShellUpdates.updateAvailable ? "update" : "none",
            fixData: "",
            fixLabel: ShellUpdates.updateAvailable ? qsTr("Update") : ""
        });

        // Every feature gets version-checked once its root half is installed;
        // upgradeOnly gates only the fresh-install suggestion (max-perf and
        // anti-heat fit any chassis, dynamic targets desktops, bed mode is
        // ThinkPad-only and installs from the battery popout instead)
        const rootHalves = [
            {dir: "max-perf", name: qsTr("max-perf")},
            {dir: "anti-heat", name: qsTr("anti-heat")},
            {dir: "dynamic", name: qsTr("dynamic performance"), upgradeOnly: SysInfo.isLaptop},
            {dir: "bed-mode", name: qsTr("bed mode"), upgradeOnly: true}
        ];
        for (const h of rootHalves) {
            const v = vers[h.dir] ?? {repo: 0, inst: 0, enabled: false};
            if (v.enabled && v.repo > v.inst) {
                rows.push({
                    id: `roothalf-${h.dir}`,
                    name: qsTr("%1 root half outdated (v%2, current v%3)").arg(h.name).arg(v.inst).arg(v.repo),
                    detail: qsTr("The installed privileged half is from an older Caelestia++ — update to get the latest behaviour"),
                    status: "warn",
                    fixType: "roothalf",
                    fixData: h.dir,
                    fixLabel: qsTr("Update"),
                    prompt: true
                });
            } else if (!v.enabled && !h.upgradeOnly) {
                rows.push({
                    id: `roothalf-${h.dir}`,
                    name: qsTr("%1 root half missing").arg(h.name),
                    detail: qsTr("The %1 feature stays inactive until its privileged half is installed (asks for your password)").arg(h.name),
                    status: "warn",
                    fixType: "roothalf",
                    fixData: h.dir,
                    fixLabel: qsTr("Install")
                });
            } else if (v.enabled) {
                rows.push({
                    id: `roothalf-${h.dir}`,
                    name: qsTr("%1 root half installed and current").arg(h.name),
                    detail: qsTr("Feature fully available"),
                    status: "ok",
                    fixType: "none",
                    fixData: "",
                    fixLabel: ""
                });
            }
        }

        rows.push({
            id: "ignorepkg",
            name: flags.ignpkg === "ok" ? qsTr("Pacman IgnorePkg set") : qsTr("Pacman IgnorePkg not set"),
            detail: flags.ignpkg === "ok" ? qsTr("Repo packages won't clobber the git checkout") : qsTr("A caelestia++ repo package could overwrite this checkout on -Syu"),
            status: flags.ignpkg === "ok" ? "ok" : "warn",
            fixType: flags.ignpkg === "ok" ? "none" : "ignorepkg",
            fixData: "",
            fixLabel: flags.ignpkg === "ok" ? "" : qsTr("Fix")
        });

        rows.push({
            id: "face",
            name: flags.face === "ok" ? qsTr("Avatar set") : qsTr("No avatar (~/.face)"),
            detail: flags.face === "ok" ? qsTr("Dashboard user card has a picture") : qsTr("Cosmetic: click the avatar in the dashboard to set one"),
            status: flags.face === "ok" ? "ok" : "info",
            fixType: "none",
            fixData: "",
            fixLabel: ""
        });

        rows.push({
            id: "log-errors",
            name: DebugConsole.errorCount > 0 ? qsTr("%1 errors in the shell log").arg(DebugConsole.errorCount) : qsTr("No errors in the shell log"),
            detail: DebugConsole.errorCount > 0 ? qsTr("See the console tab; copy diagnostics collects the distinct ones") : qsTr("This session so far"),
            status: DebugConsole.errorCount > 0 ? "warn" : "ok",
            fixType: "none",
            fixData: "",
            fixLabel: ""
        });

        // Problems first, then untouchable info rows, healthy last
        const rank = {fail: 0, warn: 1, info: 2, ok: 3};
        rows.sort((a, b) => rank[a.status] - rank[b.status]);
        results = rows;
        lastScan = Qt.formatTime(new Date(), "hh:mm:ss");
        scanning = false;

        const freshPackages = missingPackages.filter(p => !dismissedPackages.includes(p));
        const freshHalves = outdatedRootHalves.filter(dir => (vers[dir]?.repo ?? 0) > (dismissedRootHalves[dir] ?? 0));
        if ((freshPackages.length || freshHalves.length) && !DebugConsole.open)
            promptOpen = true;
    }

    Process {
        id: probe

        stdout: StdioCollector {
            onStreamFinished: root._finish(text)
        }
    }

    Process {
        id: fixProc

        onExited: {
            root.busyId = "";
            root.scan();
        }
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", Paths.state]
    }

    FileView {
        id: store

        path: root.statePath
        printErrors: false

        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.dismissedPackages = saved.dismissedPackages ?? [];
                root.dismissedRootHalves = saved.dismissedRootHalves ?? {};
            } catch (e) {}
        }
    }

    // First scan waits out the startup rush; the shell is fully up by then
    Timer {
        running: true
        interval: 15000
        onTriggered: root.scan()
    }

    Component.onCompleted: ensureStateDir.running = true

    IpcHandler {
        target: "systemcheck"

        function scan(): void {
            root.scan();
        }
        function status(): string {
            return root.results.map(r => `${r.status.toUpperCase()} ${r.name}`).join("\n");
        }
    }
}
