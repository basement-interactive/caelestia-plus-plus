pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bridge to the HyprMod Hyprland-customizer layer. Three surfaces, all through hyprmod-ctl.py:
// curated scalar knobs from variables.lua, arbitrary option overrides on top
// of the lua config, and custom keybinds. Writes are optimistic in the UI and
// serialized through a queue so rapid changes never race the helper's
// read-modify-write.
Singleton {
    id: root

    readonly property string ctl: Quickshell.shellPath("assets/hyprmod-ctl.py")

    property bool available
    property var knobs: ({})

    // Full option surface: hyprctl descriptions entries + override state
    property var schema: []
    property var overrides: ({})
    property var customBinds: []

    property var pendingCommands: []

    function get(key: string, fallback: var): var {
        return knobs[key] !== undefined ? knobs[key] : fallback;
    }

    function set(key: string, value: var): void {
        const updated = Object.assign({}, knobs);
        updated[key] = value;
        knobs = updated;
        enqueue(["set", key, String(value)], key);
    }

    function optionValue(option: var): var {
        if (overrides[option.name] !== undefined)
            return overrides[option.name];
        return option.current !== null ? option.current : option.default;
    }

    function setOption(name: string, value: var): void {
        const updated = Object.assign({}, overrides);
        updated[name] = value;
        overrides = updated;
        enqueue(["set-option", name, String(value)], name);
    }

    function unsetOption(name: string): void {
        const updated = Object.assign({}, overrides);
        delete updated[name];
        overrides = updated;
        enqueue(["unset-option", name], name);
    }

    function addBind(combo: string, kind: string, value: string, flags: string): void {
        enqueue(["add-bind", combo, kind, value, flags], null);
    }

    function delBind(index: int): void {
        enqueue(["del-bind", String(index)], null);
    }

    function refreshSchema(): void {
        schemaProc.running = true;
        overridesProc.running = true;
    }

    // collapseKey: queued commands with the same non-null key are superseded
    // by the newest one (slider spam); bind edits always run in order.
    function enqueue(command: var, collapseKey: var): void {
        if (collapseKey !== null)
            pendingCommands = pendingCommands.filter(entry => entry.key !== collapseKey);
        pendingCommands = pendingCommands.concat([{
            key: collapseKey,
            command
        }]);
        runQueue();
    }

    function runQueue(): void {
        if (ctlProc.running || !pendingCommands.length)
            return;
        const entry = pendingCommands[0];
        pendingCommands = pendingCommands.slice(1);
        ctlProc.command = ["python3", ctl].concat(entry.command);
        ctlProc.running = true;
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
        id: schemaProc

        command: ["python3", root.ctl, "schema"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.schema = JSON.parse(text);
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: overridesProc

        command: ["python3", root.ctl, "overrides"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.overrides = state.options;
                    root.customBinds = state.binds;
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: ctlProc

        onExited: {
            root.runQueue();
            // Bind list mutations come back from the helper's state file
            if (!ctlProc.running)
                overridesProc.running = true;
        }
    }
}
