pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

// System health scanner behind the debug window's "System scan" tab. Probes
// the shell's runtime needs (binaries, daemons, privileged halves, updates)
// plus Hyprland and general system health: config errors, broken configs,
// failed units, package corruption, orphans, audio stack, locale, disk.
//
// Every finding can carry a fix descriptor; nothing runs directly. A fix is
// staged as `pendingFix` — the UI shows its exact commands and what they
// change, and only confirmPendingFix() executes them (root work through
// pkexec, so the user only ever types a password).
//
// A scan also runs once at startup: missing packages and outdated privileged
// halves raise SetupPrompt (modules/debug) with the same confirm-first flow.
Singleton {
    id: root

    property bool scanning
    property string lastScan
    property string busyId

    // [{id, name, detail, status: ok|warn|fail|info, prompt?, fix?}]
    // fix: {label, summary, commands: [display strings], exec: [argv], kind?}
    property var results: []
    readonly property int problemCount: results.filter(r => r.status === "warn" || r.status === "fail").length
    readonly property var missingPackages: results.filter(r => r.fix?.pkg).map(r => r.fix.pkg)

    // Rows that warrant the unprompted startup dialog: missing packages and
    // outdated (already installed) privileged halves
    readonly property var promptItems: results.filter(r => r.prompt)
    readonly property var outdatedRootHalves: results.filter(r => r.prompt && r.id.startsWith("roothalf-")).map(r => r.fix.dir)

    // Staged fix awaiting user confirmation: {id, title, summary, commands, exec, kind}
    property var pendingFix: null

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
        // One shell probe, one machine-readable line per check. Values never
        // contain "|" (tr'd away). Kept ${}-free: this is a JS template.
        probe.command = ["sh", "-c", `
for b in ${bins}; do command -v "$b" >/dev/null 2>&1 && echo "bin|$b|ok" || echo "bin|$b|missing"; done
systemctl is-active -q power-profiles-daemon 2>/dev/null && echo "ppd|active" || echo "ppd|inactive"
[ -f "$HOME/.face" ] && echo "face|ok" || echo "face|missing"
grep -qs 'IgnorePkg.*caelestia' /etc/pacman.conf && echo "ignpkg|ok" || echo "ignpkg|missing"
for f in max-perf anti-heat dynamic bed-mode; do
  repo=$(grep -m1 '^root_half_version=' "${Quickshell.shellDir}/system/$f/install.sh" 2>/dev/null | cut -d= -f2)
  [ -n "$repo" ] || repo=0
  inst=$(cat "/etc/caelestia/$f.version" 2>/dev/null || echo 0)
  if systemctl is-enabled -q "$f-sync.path" 2>/dev/null; then en=1; else en=0; fi
  echo "ver|$f|$repo|$inst|$en"
done
hc=$(hyprctl configerrors 2>/dev/null | grep -vi 'no errors' | grep .) || true
echo "hyprerr|$(printf '%s' "$hc" | grep -c .)|$(printf '%s' "$hc" | head -1 | cut -c1-140 | tr '|' '/')"
for p in xdg-desktop-portal-hyprland qt6-wayland; do pacman -Q "$p" >/dev/null 2>&1 && echo "pkg|$p|ok" || echo "pkg|$p|missing"; done
echo "portals|$(pacman -Qq 2>/dev/null | grep '^xdg-desktop-portal-' | grep -v hyprland | grep -v gtk | tr '\\n' ' ')"
pgrep -f 'polkit-gnome-auth|polkit-kde-auth|lxpolkit|hyprpolkitagent|mate-polkit|xfce-polkit' >/dev/null && echo "polkitagent|ok" || echo "polkitagent|missing"
for c in "$HOME/.config/caelestia/"*.json; do
  [ -e "$c" ] || continue
  python3 -m json.tool "$c" >/dev/null 2>&1 && echo "cfgjson|$c|ok" || echo "cfgjson|$c|bad"
done
echo "gitdirty|$(git -C '${Quickshell.shellDir}' status --porcelain 2>/dev/null | grep -c .)"
echo "failed|$(systemctl --failed --no-legend --plain 2>/dev/null | grep -c .)|$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\\n' ' ')"
echo "userfailed|$(systemctl --user --failed --no-legend --plain 2>/dev/null | grep -c .)|$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\\n' ' ')"
echo "journal|$(journalctl -b -p err -q --no-pager 2>/dev/null | grep -c .)"
if [ -e /var/lib/pacman/db.lck ] && ! pgrep -x pacman >/dev/null; then echo "paclock|stale"; else echo "paclock|ok"; fi
echo "orphans|$(pacman -Qtdq 2>/dev/null | grep -c .)|$(pacman -Qtdq 2>/dev/null | head -10 | tr '\\n' ' ')"
echo "paccache|$(du -sBG /var/cache/pacman/pkg 2>/dev/null | cut -f1 | tr -d G)|$(command -v paccache >/dev/null && echo 1 || echo 0)"
echo "disk|$(df --output=pcent / 2>/dev/null | tail -1 | tr -d ' %')"
if command -v pactl >/dev/null; then echo "dupsinks|$(pactl list short sinks 2>/dev/null | awk '{print $2}' | sort | uniq -d | tr '\\n' ' ')"; else echo "dupsinks|"; fi
systemctl --user is-active -q pipewire 2>/dev/null && echo "pipewire|active" || echo "pipewire|inactive"
if locale 2>&1 >/dev/null | grep -q .; then echo "locale|bad"; else echo "locale|ok"; fi
echo "ntp|$(timedatectl show -p NTP --value 2>/dev/null)"
cor=$(pacman -Qk 2>/dev/null | awk -F': ' '$2 !~ /, 0 missing/ {sub(/:$/, "", $1); print $1}') || true
echo "corrupt|$(printf '%s' "$cor" | grep -c .)|$(printf '%s' "$cor" | head -8 | tr '\\n' ' ')"
`];
        probe.running = true;
    }

    // --- Fix staging: nothing executes without an explicit confirm ----------

    function requestFix(id: string): void {
        const r = results.find(x => x.id === id);
        if (!r?.fix || busyId)
            return;
        pendingFix = Object.assign({id: r.id, title: r.name}, r.fix);
    }

    // Scan-tab "install all missing" bundle
    function requestInstallAll(): void {
        if (!missingPackages.length || busyId)
            return;
        const cmd = "pacman -S --needed --noconfirm " + missingPackages.join(" ");
        pendingFix = {
            id: "all",
            title: qsTr("Install %1 missing packages").arg(missingPackages.length),
            summary: qsTr("Installs the packages the shell needs through pacman, as root via pkexec. Nothing is removed or reconfigured."),
            commands: [cmd],
            exec: ["pkexec", "sh", "-c", cmd]
        };
    }

    // Startup-prompt bundle: missing packages + outdated privileged halves,
    // one pkexec for everything
    function requestFixAll(): void {
        if (busyId)
            return;
        const commands = [];
        if (missingPackages.length)
            commands.push("pacman -S --needed --noconfirm " + missingPackages.join(" "));
        for (const dir of outdatedRootHalves)
            commands.push(`bash '${Quickshell.shellDir}/system/${dir}/install.sh'`);
        if (!commands.length)
            return;
        pendingFix = {
            id: "all",
            title: qsTr("Fix everything found"),
            summary: qsTr("Installs missing packages and re-runs the installers of outdated privileged components (they overwrite their own files under /usr/local/bin and /etc/systemd/system, then restart their units). One password, everything runs as root via pkexec."),
            commands: commands,
            exec: ["pkexec", "sh", "-c", commands.join(" && ")]
        };
    }

    function confirmPendingFix(): void {
        const fix = pendingFix;
        pendingFix = null;
        if (!fix || busyId)
            return;
        if (fix.kind === "update") {
            ShellUpdates.update();
            return;
        }
        busyId = fix.id;
        fixProc.command = fix.exec;
        fixProc.running = true;
    }

    function cancelPendingFix(): void {
        pendingFix = null;
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

    // --- Row builders --------------------------------------------------------

    function _rootFix(summary: string, commands: var): var {
        return {summary: summary, commands: commands, exec: ["pkexec", "sh", "-c", commands.join(" && ")]};
    }

    function _userFix(summary: string, commands: var): var {
        return {summary: summary, commands: commands, exec: ["sh", "-c", commands.join(" && ")]};
    }

    function _finish(out: string): void {
        const flags = {};
        const vers = {};
        const cfgs = [];
        for (const line of out.trim().split("\n")) {
            const parts = line.split("|");
            if (parts[0] === "ver")
                vers[parts[1]] = {repo: parseInt(parts[2], 10) || 0, inst: parseInt(parts[3], 10) || 0, enabled: parts[4] === "1"};
            else if (parts[0] === "cfgjson")
                cfgs.push({file: parts[1], ok: parts[2] === "ok"});
            else if (parts[0] === "bin" || parts[0] === "pkg")
                flags[`${parts[0]}.${parts[1]}`] = parts[2];
            else
                flags[parts[0]] = parts.slice(1);
        }
        _verState = vers;

        const rows = [];
        const push = (id, name, detail, status, extra) => rows.push(Object.assign({id, name, detail, status}, extra ?? {}));

        // -- Shell runtime dependencies
        for (const b of binaries) {
            if (b.laptopOnly && !SysInfo.isLaptop)
                continue;
            const ok = flags[`bin.${b.bin}`] === "ok";
            push(`bin-${b.bin}`, ok ? qsTr("%1 installed").arg(b.pkg) : qsTr("%1 missing").arg(b.pkg), b.why, ok ? "ok" : b.severity, ok ? null : {
                prompt: true,
                fix: Object.assign({label: qsTr("Install"), pkg: b.pkg}, _rootFix(qsTr("Installs the %1 package with pacman. Nothing is removed.").arg(b.pkg), [`pacman -S --needed --noconfirm ${b.pkg}`]))
            });
        }

        if (flags["bin.powerprofilesctl"] === "ok") {
            const active = flags.ppd?.[0] === "active";
            push("ppd-service", active ? qsTr("power-profiles-daemon running") : qsTr("power-profiles-daemon not running"), qsTr("The daemon behind power profile switching"), active ? "ok" : "warn", active ? null : {
                fix: Object.assign({label: qsTr("Enable")}, _rootFix(qsTr("Enables and starts the power-profiles-daemon system service."), ["systemctl enable --now power-profiles-daemon"]))
            });
        }

        // -- Caelestia: updates, privileged halves, config, checkout
        push("shell-updates", ShellUpdates.updateAvailable ? qsTr("Shell %1 commits behind").arg(ShellUpdates.commitsBehind) : qsTr("Shell up to date"), ShellUpdates.updateAvailable ? qsTr("Newer Caelestia++ is on origin/main") : qsTr("Checked against origin/main"), ShellUpdates.updateAvailable ? "warn" : "ok", ShellUpdates.updateAvailable ? {
            fix: {label: qsTr("Update"), kind: "update", summary: qsTr("Pulls origin/main into the shell checkout and reloads the shell. Local files are not touched beyond git's fast-forward."), commands: ["git pull --ff-only origin main"]}
        } : null);

        const rootHalves = [
            {dir: "max-perf", name: qsTr("max-perf")},
            {dir: "anti-heat", name: qsTr("anti-heat")},
            {dir: "dynamic", name: qsTr("dynamic performance"), upgradeOnly: SysInfo.isLaptop},
            {dir: "bed-mode", name: qsTr("bed mode"), upgradeOnly: true}
        ];
        for (const h of rootHalves) {
            const v = vers[h.dir] ?? {repo: 0, inst: 0, enabled: false};
            const installFix = label => Object.assign({label, dir: h.dir}, _rootFix(qsTr("Runs system/%1/install.sh from the checkout as root: copies its scripts to /usr/local/bin, its units to /etc/systemd/system, and enables the watcher unit. Overwrites previous versions of the same files only.").arg(h.dir), [`bash '${Quickshell.shellDir}/system/${h.dir}/install.sh'`]));
            if (v.enabled && v.repo > v.inst)
                push(`roothalf-${h.dir}`, qsTr("%1 root half outdated (v%2, current v%3)").arg(h.name).arg(v.inst).arg(v.repo), qsTr("The installed privileged half is from an older Caelestia++ — update to get the latest behaviour"), "warn", {prompt: true, fix: installFix(qsTr("Update"))});
            else if (!v.enabled && !h.upgradeOnly)
                push(`roothalf-${h.dir}`, qsTr("%1 root half missing").arg(h.name), qsTr("The %1 feature stays inactive until its privileged half is installed").arg(h.name), "warn", {fix: installFix(qsTr("Install"))});
            else if (v.enabled)
                push(`roothalf-${h.dir}`, qsTr("%1 root half installed and current").arg(h.name), qsTr("Feature fully available"), "ok");
        }

        for (const c of cfgs)
            push(`cfg-${c.file}`, c.ok ? qsTr("Config valid: %1").arg(c.file.split("/").pop()) : qsTr("Config is not valid JSON: %1").arg(c.file.split("/").pop()), c.ok ? c.file : qsTr("%1 — the shell falls back to defaults while this file is broken").arg(c.file), c.ok ? "ok" : "fail", c.ok ? null : {
                fix: Object.assign({label: qsTr("Reset")}, _userFix(qsTr("Moves the broken file aside (a .broken.bak copy stays next to it, nothing is deleted); the shell then regenerates defaults."), [`mv '${c.file}' '${c.file}.broken.bak'`]))
            });

        const dirty = parseInt(flags.gitdirty?.[0] ?? "0", 10);
        push("git-dirty", dirty > 0 ? qsTr("Shell checkout has %1 modified files").arg(dirty) : qsTr("Shell checkout clean"), dirty > 0 ? qsTr("Local edits are fine, but they can conflict with updates — no automatic action") : qsTr("No local modifications"), dirty > 0 ? "info" : "ok");

        push("ignorepkg", flags.ignpkg?.[0] === "ok" ? qsTr("Pacman IgnorePkg set") : qsTr("Pacman IgnorePkg not set"), flags.ignpkg?.[0] === "ok" ? qsTr("Repo packages won't clobber the git checkout") : qsTr("A caelestia++ repo package could overwrite this checkout on -Syu"), flags.ignpkg?.[0] === "ok" ? "ok" : "warn", flags.ignpkg?.[0] === "ok" ? null : {
            fix: Object.assign({label: qsTr("Fix")}, _rootFix(qsTr("Appends one IgnorePkg line to /etc/pacman.conf so system updates skip the caelestia++ packages. No other line is touched."), ["printf 'IgnorePkg = caelestia++-shell caelestia++-cli\\n' >> /etc/pacman.conf"]))
        });

        // -- Hyprland
        const hyprErrs = parseInt(flags.hyprerr?.[0] ?? "0", 10);
        push("hypr-config", hyprErrs > 0 ? qsTr("Hyprland config has %1 errors").arg(hyprErrs) : qsTr("Hyprland config parses clean"), hyprErrs > 0 ? qsTr("First: %1 — full list via `hyprctl configerrors`; needs a manual edit").arg(flags.hyprerr?.[1] ?? "") : qsTr("hyprctl configerrors reports none"), hyprErrs > 0 ? "fail" : "ok");

        for (const p of ["xdg-desktop-portal-hyprland", "qt6-wayland"]) {
            const ok = flags[`pkg.${p}`] === "ok";
            push(`pkg-${p}`, ok ? qsTr("%1 installed").arg(p) : qsTr("%1 missing").arg(p), p === "qt6-wayland" ? qsTr("Qt apps need it to run natively on Wayland") : qsTr("Screen sharing and file pickers break without the Hyprland portal"), ok ? "ok" : "fail", ok ? null : {
                prompt: true,
                fix: Object.assign({label: qsTr("Install"), pkg: p}, _rootFix(qsTr("Installs the %1 package with pacman. Nothing is removed.").arg(p), [`pacman -S --needed --noconfirm ${p}`]))
            });
        }

        const extraPortals = (flags.portals?.[0] ?? "").trim();
        push("portals-extra", extraPortals ? qsTr("Extra desktop portals installed") : qsTr("No conflicting desktop portals"), extraPortals ? qsTr("%1 — apps can pick the wrong portal and hang on start; remove them manually if you see slow app launches").arg(extraPortals) : qsTr("Only the Hyprland (and gtk) portals are present"), extraPortals ? "info" : "ok");

        const agentOk = flags.polkitagent?.[0] === "ok";
        push("polkit-agent", agentOk ? qsTr("Polkit agent running") : qsTr("No polkit authentication agent running"), agentOk ? qsTr("Password prompts for privileged actions work") : qsTr("Without one, no password dialog can appear — including these quick fixes. Install one and add it to Hyprland's exec-once."), agentOk ? "ok" : "fail", agentOk ? null : {
            fix: Object.assign({label: qsTr("Install")}, _rootFix(qsTr("Installs the hyprpolkitagent package. You still need to add `exec-once = systemctl --user start hyprpolkitagent` to your Hyprland config — that part is not automated."), ["pacman -S --needed --noconfirm hyprpolkitagent"]))
        });

        // -- System health
        const failedSys = parseInt(flags.failed?.[0] ?? "0", 10);
        const failedUser = parseInt(flags.userfailed?.[0] ?? "0", 10);
        if (failedSys + failedUser > 0) {
            const names = `${flags.failed?.[1] ?? ""} ${flags.userfailed?.[1] ?? ""}`.trim();
            const commands = [];
            if (failedUser > 0)
                commands.push("systemctl --user reset-failed");
            if (failedSys > 0)
                commands.push("pkexec systemctl reset-failed");
            push("failed-units", qsTr("%1 systemd units failed").arg(failedSys + failedUser), qsTr("%1 — check them with `systemctl status <unit>`; the quick fix only clears the failed markers, it does not repair the services").arg(names), "warn", {
                fix: Object.assign({label: qsTr("Clear")}, _userFix(qsTr("Clears systemd's failed-unit markers (user units directly, system units via pkexec). Purely cosmetic: the underlying services are NOT repaired and will show up again if they fail again."), commands))
            });
        } else {
            push("failed-units", qsTr("No failed systemd units"), qsTr("System and user managers are clean"), "ok");
        }

        const lockStale = flags.paclock?.[0] === "stale";
        push("pacman-lock", lockStale ? qsTr("Stale pacman database lock") : qsTr("Pacman database unlocked"), lockStale ? qsTr("db.lck exists but no pacman process is running — every install will fail until it is removed") : qsTr("No leftover db.lck"), lockStale ? "fail" : "ok", lockStale ? {
            fix: Object.assign({label: qsTr("Remove")}, _rootFix(qsTr("Deletes /var/lib/pacman/db.lck. Safe only because the scan verified no pacman process is running right now."), ["rm /var/lib/pacman/db.lck"]))
        } : null);

        const corrupt = parseInt(flags.corrupt?.[0] ?? "0", 10);
        push("corrupt-pkgs", corrupt > 0 ? qsTr("%1 packages have missing files").arg(corrupt) : qsTr("All package files present"), corrupt > 0 ? qsTr("%1 — files these packages installed are gone from disk (deleted or corrupted); reinstalling restores them").arg(flags.corrupt?.[1] ?? "") : qsTr("pacman -Qk finds nothing missing"), corrupt > 0 ? "warn" : "ok", corrupt > 0 ? {
            fix: Object.assign({label: qsTr("Reinstall")}, _rootFix(qsTr("Reinstalls the affected packages with pacman, restoring their missing files. Configs in /etc marked as backup files are preserved by pacman."), ["pacman -S --noconfirm $(pacman -Qk 2>/dev/null | awk -F': ' '$2 !~ /, 0 missing/ {sub(/:$/, \"\", $1); print $1}')"]))
        } : null);

        const orphans = parseInt(flags.orphans?.[0] ?? "0", 10);
        push("orphans", orphans > 0 ? qsTr("%1 orphaned packages").arg(orphans) : qsTr("No orphaned packages"), orphans > 0 ? qsTr("Installed as dependencies, no longer needed by anything: %1%2").arg(flags.orphans?.[1] ?? "").arg(orphans > 10 ? "…" : "") : qsTr("pacman -Qtdq is empty"), orphans > 0 ? "info" : "ok", orphans > 0 ? {
            fix: Object.assign({label: qsTr("Remove")}, _rootFix(qsTr("Removes all orphaned packages and their now-unneeded dependencies (pacman -Rns). Review the list first — anything you want to keep should be reinstalled explicitly or marked with `pacman -D --asexplicit`."), ["pacman -Rns --noconfirm $(pacman -Qtdq)"]))
        } : null);

        const cacheGB = parseInt(flags.paccache?.[0] ?? "0", 10);
        const hasPaccache = flags.paccache?.[1] === "1";
        if (cacheGB >= 8)
            push("pac-cache", qsTr("Package cache is %1 GiB").arg(cacheGB), hasPaccache ? qsTr("Old package versions pile up in /var/cache/pacman/pkg") : qsTr("Old package versions pile up in /var/cache/pacman/pkg — install pacman-contrib for the paccache cleaner"), "info", hasPaccache ? {
                fix: Object.assign({label: qsTr("Clean")}, _rootFix(qsTr("Runs paccache -rk2: deletes cached package files except the two most recent versions of each package. Installed software is not affected."), ["paccache -rk2"]))
            } : null);

        const diskPct = parseInt(flags.disk?.[0] ?? "0", 10);
        push("disk-root", diskPct >= 90 ? qsTr("Root filesystem %1% full").arg(diskPct) : qsTr("Root filesystem at %1%").arg(diskPct), diskPct >= 90 ? qsTr("Things start failing in odd ways when / fills up — free some space") : qsTr("Plenty of room"), diskPct >= 95 ? "fail" : diskPct >= 90 ? "warn" : "ok");

        // -- Audio
        const pipewireOk = flags.pipewire?.[0] === "active";
        push("pipewire", pipewireOk ? qsTr("PipeWire running") : qsTr("PipeWire not running"), pipewireOk ? qsTr("Audio stack is up") : qsTr("No audio and no visualiser without it"), pipewireOk ? "ok" : "fail", pipewireOk ? null : {
            fix: Object.assign({label: qsTr("Start")}, _userFix(qsTr("Enables and starts your user's pipewire, pipewire-pulse and wireplumber services. No configuration is changed."), ["systemctl --user enable --now pipewire pipewire-pulse wireplumber"]))
        });

        const dupSinks = (flags.dupsinks?.[0] ?? "").trim();
        push("dup-sinks", dupSinks ? qsTr("Duplicate audio sinks") : qsTr("No duplicate audio sinks"), dupSinks ? qsTr("%1 — the same device shows up twice (usually a stale ALSA/PipeWire profile); restarting the audio stack rebuilds the device list").arg(dupSinks) : qsTr("Each output device appears once"), dupSinks ? "warn" : "ok", dupSinks ? {
            fix: Object.assign({label: qsTr("Restart audio")}, _userFix(qsTr("Restarts your user's pipewire, pipewire-pulse and wireplumber services. Audio cuts out for a second or two; apps reconnect automatically."), ["systemctl --user restart pipewire pipewire-pulse wireplumber"]))
        } : null);

        // -- Misc environment
        push("locale", flags.locale?.[0] === "bad" ? qsTr("Broken locale configuration") : qsTr("Locale configuration valid"), flags.locale?.[0] === "bad" ? qsTr("`locale` prints errors — apps misbehave with unset locales. Fix /etc/locale.gen (uncomment your locale), run locale-gen, and set LANG in /etc/locale.conf — machine-specific, so no automatic fix") : qsTr("locale reports no errors"), flags.locale?.[0] === "bad" ? "warn" : "ok");

        const ntpOn = (flags.ntp?.[0] ?? "yes") !== "no";
        push("ntp", ntpOn ? qsTr("Clock synchronisation on") : qsTr("Clock synchronisation off"), ntpOn ? qsTr("systemd-timesyncd keeps the clock right") : qsTr("A drifting clock breaks TLS and package signatures eventually"), ntpOn ? "ok" : "info", ntpOn ? null : {
            fix: Object.assign({label: qsTr("Enable")}, _rootFix(qsTr("Runs timedatectl set-ntp true, enabling systemd's time synchronisation."), ["timedatectl set-ntp true"]))
        });

        const journalErrs = parseInt(flags.journal?.[0] ?? "0", 10);
        push("journal-errors", journalErrs > 0 ? qsTr("%1 error-level journal entries this boot").arg(journalErrs) : qsTr("No error-level journal entries this boot"), journalErrs > 0 ? qsTr("Not all are serious — read them with `journalctl -b -p err`") : qsTr("journalctl -b -p err is empty"), journalErrs > 0 ? "info" : "ok");

        push("face", flags.face?.[0] === "ok" ? qsTr("Avatar set") : qsTr("No avatar (~/.face)"), flags.face?.[0] === "ok" ? qsTr("Dashboard user card has a picture") : qsTr("Cosmetic: click the avatar in the dashboard to set one"), flags.face?.[0] === "ok" ? "ok" : "info");

        push("log-errors", DebugConsole.errorCount > 0 ? qsTr("%1 errors in the shell log").arg(DebugConsole.errorCount) : qsTr("No errors in the shell log"), DebugConsole.errorCount > 0 ? qsTr("See the console tab; copy diagnostics collects the distinct ones") : qsTr("This session so far"), DebugConsole.errorCount > 0 ? "warn" : "ok");

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

        stdout: SplitParser {
            onRead: data => console.info("systemcheck fix:", data)
        }
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
