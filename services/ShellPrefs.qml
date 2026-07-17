pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Small shell-owned preferences that don't belong in the compiled config
// schema (shell.json). Persisted to state and hot-reloaded on change, same
// pattern as Features.
Singleton {
    id: root

    readonly property string statePath: `${Paths.state}/prefs.json`

    // Bar logo style: true = oversized distro logo capping the pill's left
    // end; false = regular-size logo inside the pill with normal rounding
    readonly property bool barLogoEndcap: props.barLogoEndcap

    function setBarLogoEndcap(value: bool): void {
        if (value === props.barLogoEndcap)
            return;
        props.barLogoEndcap = value;
        save();
    }

    function save(): void {
        store.setText(JSON.stringify({
            barLogoEndcap: props.barLogoEndcap
        }, null, 2) + "\n");
    }

    QtObject {
        id: props

        property bool barLogoEndcap: true
    }

    FileView {
        id: store

        path: root.statePath
        watchChanges: true
        printErrors: false

        onLoaded: {
            let saved;
            try {
                saved = JSON.parse(text());
            } catch (e) {
                return;
            }
            props.barLogoEndcap = saved.barLogoEndcap ?? true;
        }
        onFileChanged: reload()
    }
}
