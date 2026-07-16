pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

// "Maximum performance" mode: pin the machine at its limits. Like BedMode,
// this singleton only flips a plain state file it owns; the privileged work
// (ryzenadj 42/50/45W loop, pinned governor, amdgpu high, thinkfan-max) runs
// root-side via a path unit. See system/max-perf/ for that half and the
// one-time `sudo install.sh` it needs — `installed` tracks whether that has
// been done, because without it this toggle is power-profile-and-eye-candy
// only and the fans never change.
//
// Mutually exclusive with BedMode (opposite fan curves), and drags GameMode
// along so the compositor sheds its eye candy too.
Singleton {
    id: root

    readonly property string statePath: "/home/john/.local/state/caelestia/max-perf"
    readonly property bool enabled: stateFile.checked
    // True once system/max-perf/install.sh has been run (root path unit exists).
    property bool installed: false

    function setEnabled(value: bool): void {
        if (value === root.enabled)
            return;

        stateFile.checked = value;
        stateFile.setText(value ? "1\n" : "0\n");

        if (value) {
            BedMode.setEnabled(false);
            Dynamic.setEnabled(false); // Dynamic and Max-perf both drive the profile; never both
        }
        // Not PowerProfiles.profile: quickshell's UPower service mis-detects
        // performance as unavailable on this machine (ppd has it fine).
        Quickshell.execDetached(["powerprofilesctl", "set", value ? "performance" : "balanced"]);
        GameMode.enabled = value;

        if (value && !root.installed) {
            installCheck.running = true; // re-probe in case it was just installed
            Toaster.toast(qsTr("Maximum performance (partial)"), qsTr("Root half missing — run: sudo system/max-perf/install.sh"), "warning");
        } else {
            Toaster.toast(value ? qsTr("Maximum performance engaged") : qsTr("Maximum performance off"), value ? qsTr("50W limits, pinned clocks, fans flat out from 48C") : qsTr("Power plan, clocks and fans restored"), "bolt");
        }
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", "/home/john/.local/state/caelestia"]
    }

    Process {
        id: installCheck

        command: ["systemctl", "is-enabled", "--quiet", "max-perf-sync.path"]
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
