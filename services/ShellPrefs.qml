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

    // Animated DNA background (shown when no image wallpaper is set)
    readonly property bool dnaEnabled: props.dnaEnabled
    readonly property bool dnaUseThemeColor: props.dnaUseThemeColor
    readonly property string dnaCustomColor: props.dnaCustomColor

    function setBarLogoEndcap(value: bool): void {
        if (value === props.barLogoEndcap)
            return;
        props.barLogoEndcap = value;
        save();
    }

    function setDnaEnabled(value: bool): void {
        if (value === props.dnaEnabled)
            return;
        props.dnaEnabled = value;
        save();
    }

    function setDnaUseThemeColor(value: bool): void {
        if (value === props.dnaUseThemeColor)
            return;
        props.dnaUseThemeColor = value;
        save();
    }

    function setDnaCustomColor(value: string): void {
        if (value === props.dnaCustomColor)
            return;
        props.dnaCustomColor = value;
        save();
    }

    function save(): void {
        store.setText(JSON.stringify({
            barLogoEndcap: props.barLogoEndcap,
            dnaEnabled: props.dnaEnabled,
            dnaUseThemeColor: props.dnaUseThemeColor,
            dnaCustomColor: props.dnaCustomColor
        }, null, 2) + "\n");
    }

    QtObject {
        id: props

        property bool barLogoEndcap: true
        property bool dnaEnabled: true
        property bool dnaUseThemeColor: true
        property string dnaCustomColor: "#ff5449"
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
            props.dnaEnabled = saved.dnaEnabled ?? true;
            props.dnaUseThemeColor = saved.dnaUseThemeColor ?? true;
            props.dnaCustomColor = saved.dnaCustomColor ?? "#ff5449";
        }
        onFileChanged: reload()
    }
}
