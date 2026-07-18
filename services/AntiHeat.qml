pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

// "Anti-Heat" mode: run cooler WITHOUT running slower. Like BedMode/MaxPerf,
// this singleton only flips a plain state file it owns; the privileged work
// (curve-optimizer undervolt loop + early thinkfan-cool curve) runs root-side
// via a path unit. See system/anti-heat/ for that half and the one-time
// `sudo install.sh` it needs — `installed` tracks whether that has been done,
// because without it this toggle does nothing at all.
//
// Coexists with every other mode: the undervolt is orthogonal to power
// limits, and fan arbitration is handled root-side (bed/max curves win
// while active).
Singleton {
    id: root

    readonly property string statePath: `${Paths.state}/anti-heat`
    readonly property bool enabled: stateFile.checked
    // True once system/anti-heat/install.sh has been run (root path unit exists).
    property bool installed: false
    property bool installing: false

    function setEnabled(value: bool): void {
        if (value === root.enabled)
            return;

        stateFile.checked = value;
        stateFile.setText(value ? "1\n" : "0\n");

        if (value && !root.installed && !root.installing) {
            root.installing = true;
            Toaster.toast(qsTr("Setting up Anti-Heat"), qsTr("Installing the privileged half — enter your password"), "key");
            installer.running = true;
        } else if (!root.installing) {
            Toaster.toast(value ? qsTr("Anti-Heat engaged") : qsTr("Anti-Heat off"), value ? qsTr("Undervolt applied, fans lead the heat — no speed lost") : qsTr("Stock voltage curve and fan behaviour restored"), "ac_unit");
        }
    }

    Process {
        id: installer

        command: ["pkexec", "bash", `${Quickshell.shellDir}/system/anti-heat/install.sh`]
        stdout: SplitParser {
            onRead: data => console.info("anti-heat install:", data)
        }
        onExited: code => {
            root.installing = false;
            if (code === 0) {
                root.installed = true;
                Toaster.toast(qsTr("Anti-Heat ready"), qsTr("Root half installed — the mode is now active"), "ac_unit");
            } else {
                stateFile.checked = false;
                stateFile.setText("0\n");
                Toaster.toast(qsTr("Setup not completed"), code === 126 || code === 127 ? qsTr("Authentication was dismissed — toggle again to retry") : qsTr("Installer failed (code %1) — see the debug console").arg(code), "warning");
            }
        }
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", Paths.state]
    }

    Process {
        id: installCheck

        command: ["systemctl", "is-enabled", "--quiet", "anti-heat-sync.path"]
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

    Component.onCompleted: {
        ensureStateDir.running = true;
        installCheck.running = true;
    }
}
