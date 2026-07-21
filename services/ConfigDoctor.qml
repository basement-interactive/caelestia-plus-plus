pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

// Bridge between the config plugin and the system scan's shell.json check
// (assets/config-doctor.py, run by SystemCheck). Two jobs:
//
// - Dump the shell's *runtime* config schema — the property tree the plugin
//   actually accepts plus the bar entry ids the bar can render — so the
//   doctor script never carries a hardcoded copy that could drift.
// - Keep the plugin's load complaints (unknown option, parse failure) around
//   for the scan tab; the toasts they raise flash once and are gone.
Singleton {
    id: root

    readonly property string configPath: `${Quickshell.env("HOME")}/.config/caelestia/shell.json`

    // Must match Bar.qml's DelegateChooser roles
    readonly property var barIds: ["logo", "workspaces", "spacer", "activeWindow", "firewall", "features", "sysStats", "tray", "clock", "statusIcons", "power"]

    // Complaints the plugin raised since startup, deduplicated
    property var loadComplaints: []

    function schemaJson(): string {
        return JSON.stringify({
            types: _walk(GlobalConfig, 0),
            barIds: barIds
        });
    }

    function _note(complaint: string): void {
        if (!loadComplaints.includes(complaint))
            loadComplaints = loadComplaints.concat([complaint]);
    }

    // Leaves become their JSON type name; list-likes (QML lists enumerate as
    // numeric keys) become "array"; empty subtrees are user-keyed maps whose
    // contents must never be validated
    function _walk(obj: var, depth: int): var {
        if (depth > 6)
            return "map";
        const out = {};
        let keys = 0, numeric = 0;
        for (const k in obj) {
            if (k === "objectName" || k.startsWith("_"))
                continue;
            const v = obj[k];
            const t = typeof v;
            if (t === "function")
                continue;
            keys++;
            if (/^\d+$/.test(k)) {
                numeric++;
                continue;
            }
            if (t === "object" && v !== null)
                out[k] = _walk(v, depth + 1);
            else if (t === "boolean" || t === "number" || t === "string")
                out[k] = t;
        }
        if (keys === 0)
            return "map";
        if (numeric === keys)
            return "array";
        return out;
    }

    Connections {
        target: GlobalConfig

        function onLoadFailed(error: string, screen: string): void {
            root._note(qsTr("load failed: %1").arg(error));
        }

        function onUnknownOption(key: string, screen: string): void {
            root._note(qsTr("unknown option: %1").arg(key));
        }
    }
}
