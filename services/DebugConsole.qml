pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Hidden debug console, opened by 10 rapid clicks on the bar clock or
// `qs -c caelestia ipc call debug toggle`. While the panel is open it tails
// this instance's own log through `qs log -f --pid <self>`: quickshell
// records every category to the log file regardless of stdout filtering, so
// full debug output is available without relaunching the shell in verbose
// mode.
Singleton {
    id: root

    property bool open: false
    property bool paused: false
    property bool verbose: true

    // View filters; the panel binds these and renders `lines`
    property string levelFilter: "all" // all | debug | info | warn | error
    property string query: ""

    readonly property int maxLines: 1500
    property int warnCount: 0
    property int errorCount: 0
    property string memUsage: "..."

    // Filtered view of `buffer`, capped at maxLines
    readonly property ListModel lines: ListModel {}

    // Every entry received since the panel opened: {time, level, category, message}
    readonly property var buffer: []

    // pipewire's event loop and dbus property sync log every poll iteration;
    // at debug level they drown everything else, so verbose leaves them out
    readonly property string verboseRules: "*.debug=true;quickshell.service.pipewire.loop.debug=false;quickshell.dbus.properties.debug=false"
    readonly property string quietRules: "*.debug=false"

    onOpenChanged: _restartTail()
    onVerboseChanged: _restartTail()
    onLevelFilterChanged: _refill()
    onQueryChanged: _refill()

    function clear(): void {
        buffer.length = 0;
        lines.clear();
        warnCount = 0;
        errorCount = 0;
    }

    function copyVisible(): void {
        const rows = [];
        for (let i = 0; i < lines.count; i++) {
            const l = lines.get(i);
            rows.push(`${l.time} ${l.level.toUpperCase()} ${l.category}: ${l.message}`);
        }
        Quickshell.execDetached(["wl-copy", rows.join("\n")]);
    }

    function copyDiagnostics(): void {
        Quickshell.execDetached(["wl-copy", [`Quickshell PID: ${Quickshell.processId}`, `Memory (RSS): ${memUsage}`, `Session: ${warnCount} warnings, ${errorCount} errors`, `Screens: ${Quickshell.screens.map(s => `${s.name} ${s.width}x${s.height}@${Math.round(s.devicePixelRatio * 100) / 100}x`).join(", ")}`].join("\n")]);
    }

    function _matches(entry: var): bool {
        if (levelFilter !== "all" && entry.level !== levelFilter)
            return false;
        if (query && !`${entry.category} ${entry.message}`.toLowerCase().includes(query.toLowerCase()))
            return false;
        return true;
    }

    function _refill(): void {
        lines.clear();
        for (const entry of buffer)
            if (_matches(entry))
                lines.append(entry);
    }

    function _append(raw: string): void {
        if (paused)
            return;

        // `qs log` line shape: " LEVEL category.name: message"; anything that
        // doesn't match (e.g. multiline continuations) passes through as-is
        const m = /^\s*(DEBUG|INFO|WARN|ERROR|CRITICAL|FATAL)\s+([\w.]+):\s?(.*)$/.exec(raw);
        const level = m ? m[1].toLowerCase() : "info";
        const entry = {
            time: Qt.formatTime(new Date(), "hh:mm:ss"),
            level: level === "critical" || level === "fatal" ? "error" : level,
            category: m ? m[2] : "",
            message: m ? m[3] : raw
        };

        if (entry.level === "warn")
            warnCount++;
        else if (entry.level === "error")
            errorCount++;

        buffer.push(entry);
        if (buffer.length > maxLines)
            buffer.shift();

        if (_matches(entry)) {
            lines.append(entry);
            if (lines.count > maxLines)
                lines.remove(0);
        }
    }

    // Each open starts fresh: recent history via -t, then follow. Also the
    // only way to switch rules, as `qs log` reads them once at startup.
    function _restartTail(): void {
        tail.running = false;
        if (!open)
            return;
        clear();
        tail.command = ["qs", "--no-color", "log", "-f", "-t", "200", "--pid", `${Quickshell.processId}`, "-r", verbose ? verboseRules : quietRules];
        tail.running = true;
    }

    Process {
        id: tail

        stdout: SplitParser {
            onRead: data => root._append(data)
        }
    }

    Process {
        id: memProc

        command: ["ps", "-o", "rss=", "-p", `${Quickshell.processId}`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kb = parseInt(text.trim(), 10);
                if (!isNaN(kb))
                    root.memUsage = `${(kb / 1024).toFixed(0)} MB`;
            }
        }
    }

    Timer {
        running: root.open
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: memProc.running = true
    }

    IpcHandler {
        target: "debug"

        function toggle(): void {
            root.open = !root.open;
        }
        // "show" is unusable as an IPC function name: it collides with the
        // CLI's `ipc show` subcommand and prints target info instead
        function openPanel(): void {
            root.open = true;
        }
        function closePanel(): void {
            root.open = false;
        }
    }
}
