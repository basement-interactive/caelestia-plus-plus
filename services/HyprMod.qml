pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bridge to the HyprMod compositor's runtime config. Scalar knobs from
// ~/.config/hypr/variables.lua are loaded once via the ctl helper; sets are
// optimistic in the UI and serialized through a queue so rapid changes
// (sliders, steppers) never race the helper's read-modify-write.
Singleton {
    id: root

    readonly property string ctl: Quickshell.shellPath("assets/hyprmod-ctl.py")

    property bool available
    property var knobs: ({})
    property var pendingSets: []

    function get(key: string, fallback: var): var {
        return knobs[key] !== undefined ? knobs[key] : fallback;
    }

    function set(key: string, value: var): void {
        const updated = Object.assign({}, knobs);
        updated[key] = value;
        knobs = updated;

        // Collapse queued writes to the same knob; only the newest matters
        pendingSets = pendingSets.filter(entry => entry[0] !== key).concat([[key, String(value)]]);
        runQueue();
    }

    function runQueue(): void {
        if (setProc.running || !pendingSets.length)
            return;
        const [key, value] = pendingSets[0];
        pendingSets = pendingSets.slice(1);
        setProc.command = ["python3", ctl, "set", key, value];
        setProc.running = true;
    }

    Process {
        id: dumpProc

        running: true
        command: ["python3", root.ctl, "dump"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.knobs = JSON.parse(text);
                    root.available = Object.keys(root.knobs).length > 0;
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    Process {
        id: setProc

        onExited: root.runQueue()
    }
}
