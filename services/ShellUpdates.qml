pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Update channel for the Caelestia++ fork: compares the running shell's
// checkout against origin/main on GitHub and can fast-forward + restart.
// The shell dir is a plain git clone, so "update" is just a pull — package
// files (plugin, CLI) are versioned separately and unaffected.
Singleton {
    id: root

    readonly property string repoDir: Quickshell.shellDir
    readonly property string remoteBranch: "origin/main"

    property bool checking
    property bool updating
    property int commitsBehind
    property string headCommit
    property list<string> changelog
    property string lastChecked
    property string lastError

    readonly property bool updateAvailable: commitsBehind > 0

    function check(): void {
        if (checking || updating)
            return;
        lastError = "";
        checking = true;
        checkProc.running = true;
    }

    function update(): void {
        if (updating || !updateAvailable)
            return;
        lastError = "";
        updating = true;
        updateProc.running = true;
    }

    Process {
        id: checkProc

        command: ["sh", "-c", `cd '${root.repoDir}' || exit 1
            git fetch --quiet origin main || exit 2
            echo "@head $(git rev-parse --short HEAD)"
            echo "@behind $(git rev-list --count HEAD..${root.remoteBranch})"
            git log --format=%s "HEAD..${root.remoteBranch}"`]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l);
                const head = lines.find(l => l.startsWith("@head "));
                const behind = lines.find(l => l.startsWith("@behind "));
                root.headCommit = head ? head.slice(6) : "";
                root.commitsBehind = behind ? parseInt(behind.slice(8)) || 0 : 0;
                root.changelog = lines.filter(l => !l.startsWith("@"));
            }
        }

        onExited: code => {
            root.checking = false;
            root.lastChecked = Qt.formatDateTime(new Date(), "hh:mm");
            if (code === 2)
                root.lastError = qsTr("Could not reach the update server");
            else if (code !== 0)
                root.lastError = qsTr("Update check failed");
        }
    }

    Process {
        id: updateProc

        command: ["sh", "-c", `cd '${root.repoDir}' && git pull --ff-only origin main`]

        onExited: code => {
            root.updating = false;
            if (code !== 0) {
                root.lastError = qsTr("Update failed — local changes may conflict");
                return;
            }
            // Relaunch outside our own process tree so the new checkout loads
            Quickshell.execDetached(["sh", "-c", "sleep 0.3; pkill -x qs; sleep 1; caelestia shell -d"]);
        }
    }

    // Startup check (delayed so boot isn't competing with it) + periodic recheck
    Timer {
        running: true
        interval: 20 * 1000
        onTriggered: root.check()
    }

    Timer {
        running: true
        repeat: true
        interval: 6 * 60 * 60 * 1000
        onTriggered: root.check()
    }
}
