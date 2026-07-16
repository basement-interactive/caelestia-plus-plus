pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

// "Dynamic" power mode: the fourth battery-menu profile. Instead of pinning
// one power-profiles-daemon profile, a small root daemon continuously picks
// the best of power-saver / balanced / performance from live CPU load, AC
// state and battery %. Like the sibling modes this singleton only flips a
// plain state file it owns; the picker runs root-side via a path unit. See
// system/dynamic/ for that half and the one-time `sudo install.sh` it needs —
// `installed` tracks whether that has been done.
//
// Mutually exclusive with Max-perf (which pins its own 50W plan and, when
// engaged, disables this). Coexists with Anti-Heat (orthogonal thermal caps)
// and Bed mode (which the daemon honours as a balanced ceiling).
Singleton {
    id: root

    readonly property string statePath: "/home/john/.local/state/caelestia/dynamic"
    readonly property string tierPath: "/home/john/.local/state/caelestia/dynamic-tier"
    readonly property bool enabled: stateFile.checked
    // The profile the daemon has currently selected ("power-saver"/"balanced"/
    // "performance"/"yield"), for the menu caption. Empty when unknown.
    readonly property string currentTier: tierFile.tier
    // True once system/dynamic/install.sh has been run (root path unit exists).
    property bool installed: false

    function setEnabled(value: bool): void {
        if (value === root.enabled)
            return;

        stateFile.checked = value;
        stateFile.setText(value ? "1\n" : "0\n");

        if (value)
            MaxPerf.setEnabled(false); // Max-perf owns the plan; never both

        if (value && !root.installed) {
            installCheck.running = true; // re-probe in case it was just installed
            Toaster.toast(qsTr("Dynamic (inactive)"), qsTr("Root half missing — run: sudo system/dynamic/install.sh"), "warning");
        } else {
            Toaster.toast(value ? qsTr("Dynamic power engaged") : qsTr("Dynamic power off"), value ? qsTr("Auto-switching Eco/Balanced/Performance by load and power") : qsTr("Manual power profile restored"), "auto_mode");
        }
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", "/home/john/.local/state/caelestia"]
    }

    Process {
        id: installCheck

        command: ["systemctl", "is-enabled", "--quiet", "dynamic-sync.path"]
        onExited: code => root.installed = code === 0
    }

    FileView {
        id: stateFile

        property bool checked: false

        path: root.statePath
        watchChanges: true
        printErrors: false

        onLoaded: checked = text().trim() === "1"
        onFileChanged: reload()
    }

    FileView {
        id: tierFile

        property string tier: ""

        path: root.tierPath
        watchChanges: true
        printErrors: false

        onLoaded: tier = text().trim()
        onFileChanged: reload()
    }

    Component.onCompleted: {
        ensureStateDir.running = true;
        installCheck.running = true;
    }
}
