pragma Singleton

import Quickshell
import Quickshell.Io

// Shared open/tab state for the security center (modules/protection/
// SecurityCenter.qml), the tabbed panel behind the bar shield that hosts
// Protection, Firewall, HTTP Debugger and Startup Apps. The individual data
// backends live in their own singletons (Protection, Firewall, Startup); this
// only tracks which panel is showing.
Singleton {
    id: root

    // protection | firewall | http | startup
    property string tab: "protection"
    property bool panelOpen: false

    function open(which: string): void {
        if (which)
            root.tab = which;
        root.panelOpen = true;
    }

    IpcHandler {
        target: "security"

        // NB: never name an IPC function "show" — it collides with the qs CLI
        // `ipc show` subcommand and never invokes.
        function togglePanel(): void { root.panelOpen = !root.panelOpen; }
        function openPanel(): void { root.panelOpen = true; }
        function closePanel(): void { root.panelOpen = false; }
        function openTab(which: string): void { root.open(which); }
    }
}
