pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

// Feature-mode hub behind the bar wrench. Each entry in `features` is one
// toggleable OS mode; the menu (modules/features/FeaturesMenu.qml) renders
// whatever is listed here, so adding a feature = add a descriptor below plus
// its backing implementation (or delegate to an existing service).
//
// Modes owned by this singleton (lidStay, caffeine) persist to
// ~/.local/state/caelestia/features.json and are re-applied when the shell
// starts, so they survive reboots and `caelestia shell -d` restarts alike.
// gameMode / bedMode delegate to their own services, which persist themselves.
Singleton {
    id: root

    property bool menuOpen: false

    readonly property string statePath: `${Paths.state}/features.json`
    readonly property bool lidStay: props.lidStay

    // Drives the menu and the bar badge. Rebuilt whenever any mode flips.
    // Bed mode is in the battery popout, game mode and caffeine in the
    // utilities cards. Every current entry is hardware-specific to laptops
    // (power plans, undervolt, lid), so the whole list gates on the chassis;
    // desktop-relevant features added later belong outside this guard.
    readonly property var features: !SysInfo.isLaptop ? [] : [
        {
            id: "maxPerf",
            name: qsTr("Maximum performance"),
            desc: MaxPerf.installed ? qsTr("50W power plan, pinned CPU/GPU clocks, fans flat out from 48C") : qsTr("Root half missing — run: sudo system/max-perf/install.sh"),
            icon: "bolt",
            enabled: MaxPerf.enabled
        },
        {
            id: "lidStay",
            name: qsTr("Stay awake on lid close"),
            desc: qsTr("Closing the lid neither suspends nor idles the laptop"),
            icon: "laptop_windows",
            enabled: props.lidStay
        },
        {
            id: "antiHeat",
            name: qsTr("Anti-Heat"),
            desc: AntiHeat.installed ? qsTr("Undervolt + early fans: cooler at the same speed") : qsTr("Root half missing — run: sudo system/anti-heat/install.sh"),
            icon: "ac_unit",
            enabled: AntiHeat.enabled
        }
    ]
    readonly property int activeCount: features.filter(f => f.enabled).length

    function toggle(featureId: string): void {
        switch (featureId) {
        case "lidStay":
            setLidStay(!props.lidStay);
            break;
        case "antiHeat":
            AntiHeat.setEnabled(!AntiHeat.enabled);
            break;
        case "maxPerf":
            MaxPerf.setEnabled(!MaxPerf.enabled);
            break;
        }
    }

    function setLidStay(value: bool): void {
        if (value === props.lidStay)
            return;

        props.lidStay = value;
        _save();
        Toaster.toast(value ? qsTr("Stay-awake enabled") : qsTr("Stay-awake disabled"), value ? qsTr("Lid close no longer suspends the laptop") : qsTr("Lid close suspends as usual"), "laptop_windows");
    }

    function _save(): void {
        store.setText(JSON.stringify({
            lidStay: props.lidStay,
            caffeine: IdleInhibitor.enabled
        }, null, 2) + "\n");
    }

    QtObject {
        id: props

        property bool lidStay: false
    }

    // The actual lid-close mode: a logind inhibitor lock held for as long as
    // the toggle is on. Blocks the lid-switch action (suspend), plus sleep and
    // idle so nothing else powers the machine down while it runs closed.
    Process {
        command: ["systemd-inhibit", "--what=handle-lid-switch:sleep:idle", "--who=Caelestia Features", "--why=Stay-awake mode is on", "--mode=block", "sleep", "infinity"]
        running: props.lidStay
    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", Paths.state]
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
            props.lidStay = saved.lidStay ?? false;
            IdleInhibitor.enabled = saved.caffeine ?? IdleInhibitor.enabled;
        }
        onFileChanged: reload()
    }

    Component.onCompleted: ensureStateDir.running = true

    IpcHandler {
        target: "features"

        function toggleMenu(): void { root.menuOpen = !root.menuOpen; }
        function toggleLidStay(): void { root.setLidStay(!props.lidStay); }
        function toggleMaxPerf(): void { MaxPerf.setEnabled(!MaxPerf.enabled); }
        function toggleAntiHeat(): void { AntiHeat.setEnabled(!AntiHeat.enabled); }
        function status(): string {
            return root.features.map(f => `${f.id}: ${f.enabled ? "on" : "off"}`).join("; ");
        }
    }
}
