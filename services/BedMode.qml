pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia
import qs.services

// Toggle for using the laptop somewhere airflow is restricted (e.g. in bed),
// where the fans can't dispose of heat as fast as usual. Keeps the power
// profile at Balanced but swaps in a far more sensitive fan curve.
//
// The curve itself is applied outside the shell's privilege boundary: this
// singleton only flips a plain state file that a root-owned systemd path
// unit watches. See system/bed-mode/ for the fan-curve half of this feature
// and the one-time root setup it needs.
Singleton {
    id: root

    readonly property string statePath: "/home/john/.local/state/caelestia/bed-mode"
    readonly property bool enabled: stateFile.checked

    function setEnabled(value: bool): void {
        if (value === root.enabled)
            return;

        stateFile.checked = value;
        stateFile.setText(value ? "1\n" : "0\n");

        if (value) {
            MaxPerf.setEnabled(false); // opposite fan curves; never both
            PowerProfiles.profile = PowerProfile.Balanced;
        }

        Toaster.toast(value ? qsTr("Bed mode enabled") : qsTr("Bed mode disabled"), value ? qsTr("Aggressive fan curve on, CPU boost off") : qsTr("Fan curve and CPU boost restored"), "bed");
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", "/home/john/.local/state/caelestia"]
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

    Component.onCompleted: ensureStateDir.running = true
}
