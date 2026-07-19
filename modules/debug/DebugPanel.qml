pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Debug console: a real floating window (compositor-managed, so it can stay
// open beside whatever is being debugged), opened by 10 rapid clicks on the
// bar clock. Live log tail with level filters and search, selectable text,
// plus shell diagnostics and a few maintenance actions. The capture itself
// lives in DebugConsole and runs whether or not this window exists.
Scope {
    id: root

    LazyLoader {
        active: DebugConsole.open

        FloatingWindow {
            id: win

            readonly property bool consoleTab: DebugConsole.panelTab === "console"

            color: Colours.palette.m3surfaceContainerLow
            title: qsTr("Caelestia debug console")

            implicitWidth: 940
            implicitHeight: 640
            minimumSize.width: 560
            minimumSize.height: 380

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            onVisibleChanged: {
                if (!visible)
                    DebugConsole.open = false;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                focus: true
                Keys.onEscapePressed: DebugConsole.open = false

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "bug_report"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    Column {
                        Layout.fillWidth: true

                        StyledText {
                            text: qsTr("Debug console")
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                        }

                        RowLayout {
                            spacing: 0

                            StyledText {
                                text: qsTr("PID %1  ·  %2 RSS  ·  ").arg(Quickshell.processId).arg(DebugConsole.memUsage)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }

                            StyledText {
                                text: qsTr("%1 warnings").arg(DebugConsole.warnCount)
                                color: DebugConsole.warnCount > 0 ? "#ffc233" : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }

                            StyledText {
                                text: "  ·  "
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }

                            StyledText {
                                text: qsTr("%1 errors").arg(DebugConsole.errorCount)
                                color: DebugConsole.errorCount > 0 ? "#ff5c5c" : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }
                        }
                    }

                    IconButton {
                        icon: "close"
                        type: IconButton.Text
                        onClicked: DebugConsole.open = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: qsTr("Console")
                        type: TextButton.Tonal
                        checked: win.consoleTab
                        onClicked: DebugConsole.panelTab = "console"
                    }

                    TextButton {
                        text: SystemCheck.problemCount > 0 ? qsTr("System scan (%1)").arg(SystemCheck.problemCount) : qsTr("System scan")
                        type: TextButton.Tonal
                        checked: !win.consoleTab
                        onClicked: {
                            DebugConsole.panelTab = "scan";
                            if (!SystemCheck.results.length)
                                SystemCheck.scan();
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: win.consoleTab

                    Repeater {
                        model: [
                            {id: "all", label: qsTr("All")},
                            {id: "debug", label: qsTr("Debug")},
                            {id: "info", label: qsTr("Info")},
                            {id: "warn", label: qsTr("Warn")},
                            {id: "error", label: qsTr("Error")}
                        ]

                        TextButton {
                            required property var modelData

                            text: modelData.label
                            type: TextButton.Tonal
                            checked: DebugConsole.levelFilter === modelData.id
                            onClicked: DebugConsole.levelFilter = modelData.id
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: qsTr("Verbose")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    StyledSwitch {
                        checked: DebugConsole.verbose
                        onToggled: DebugConsole.verbose = !DebugConsole.verbose
                    }

                    IconButton {
                        icon: DebugConsole.paused ? "play_arrow" : "pause"
                        type: IconButton.Tonal
                        checked: DebugConsole.paused
                        onClicked: DebugConsole.paused = !DebugConsole.paused
                    }

                    IconButton {
                        icon: "content_copy"
                        type: IconButton.Tonal
                        onClicked: {
                            if (logText.selectedText)
                                logText.copy();
                            else
                                DebugConsole.copyVisible();
                        }
                    }

                    IconButton {
                        icon: "delete_sweep"
                        type: IconButton.Tonal
                        onClicked: DebugConsole.clear()
                    }
                }

                SearchBar {
                    Layout.fillWidth: true
                    visible: win.consoleTab
                    placeholderText: qsTr("Filter by category or message")
                    onTextChanged: DebugConsole.query = text
                }

                StyledClippingRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.consoleTab
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surface

                    // Non-interactive so mouse drags select text in the
                    // TextEdit instead of flicking; scrolling is wheel +
                    // scrollbar only (the wheel catcher sits on top)
                    Flickable {
                        id: logView

                        // Follow the tail unless the user scrolled up
                        property bool stick: true

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        clip: true
                        interactive: false
                        contentWidth: width
                        contentHeight: logText.implicitHeight

                        function scrollBy(dy: real): void {
                            contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY - dy));
                            stick = contentY >= contentHeight - height - 4;
                        }

                        onContentHeightChanged: {
                            if (stick)
                                contentY = Math.max(0, contentHeight - height);
                        }

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: logView
                        }

                        TextEdit {
                            id: logText

                            function esc(s: string): string {
                                return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                            }

                            function fmt(entry: var): string {
                                const lineColour = {
                                    error: "#ff5c5c",
                                    warn: "#ffc233",
                                    debug: Colours.palette.m3outline
                                }[entry.level];
                                const levelColour = lineColour ?? Colours.palette.m3onSurfaceVariant;
                                const messageColour = lineColour ?? Colours.palette.m3onSurface;
                                return `<span style="color:${Colours.palette.m3outline}">${entry.time}</span> <span style="color:${levelColour}">${entry.level.toUpperCase()}</span> <span style="color:${lineColour ?? Colours.palette.m3secondary}">${esc(entry.category)}</span> <span style="color:${messageColour}">${esc(entry.message)}</span>`;
                            }

                            function rebuild(): void {
                                const rows = [];
                                for (let i = 0; i < DebugConsole.lines.count; i++)
                                    rows.push(fmt(DebugConsole.lines.get(i)));
                                text = rows.join("<br>");
                            }

                            width: logView.width
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                            persistentSelection: true
                            color: Colours.palette.m3onSurface
                            selectionColor: Colours.palette.m3primary
                            selectedTextColor: Colours.palette.m3onPrimary
                            font: Tokens.font.mono.small

                            Component.onCompleted: rebuild()

                            Connections {
                                target: DebugConsole

                                function onLineAppended(entry: var): void {
                                    logText.append(logText.fmt(entry));
                                }

                                function onViewReset(): void {
                                    logText.rebuild();
                                }
                            }
                        }
                    }

                    // Wheel catcher above the text: MouseArea sees scroll
                    // from both mouse wheels and touchpads (WheelHandler
                    // defaults to mouse-only devices), and with no accepted
                    // buttons every press falls through to text selection
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => logView.scrollBy(wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y)
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: DebugConsole.lines.count === 0
                        text: DebugConsole.paused ? qsTr("Paused") : qsTr("Waiting for log output…")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.medium
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: !win.consoleTab

                    StyledText {
                        text: SystemCheck.scanning ? qsTr("Scanning…") : SystemCheck.lastScan ? (SystemCheck.problemCount > 0 ? qsTr("%1 issues found · scanned %2").arg(SystemCheck.problemCount).arg(SystemCheck.lastScan) : qsTr("All good · scanned %1").arg(SystemCheck.lastScan)) : qsTr("Not scanned yet")
                        color: SystemCheck.problemCount > 0 ? "#ffc233" : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    TextButton {
                        text: SystemCheck.busyId === "all" ? qsTr("Installing…") : qsTr("Install all missing")
                        type: TextButton.Tonal
                        visible: SystemCheck.missingPackages.length > 0
                        disabled: SystemCheck.busyId !== ""
                        onClicked: SystemCheck.requestInstallAll()
                    }

                    TextButton {
                        text: qsTr("Rescan")
                        type: TextButton.Tonal
                        disabled: SystemCheck.scanning
                        onClicked: SystemCheck.scan()
                    }
                }

                StyledClippingRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !win.consoleTab
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surface

                    StyledListView {
                        id: scanList

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        clip: true
                        spacing: Tokens.spacing.small

                        model: ScriptModel {
                            values: SystemCheck.results
                        }

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: scanList
                        }

                        delegate: RowLayout {
                            id: checkRow

                            required property var modelData

                            readonly property color statusColour: {
                                switch (modelData.status) {
                                case "fail":
                                    return "#ff5c5c";
                                case "warn":
                                    return "#ffc233";
                                case "info":
                                    return Colours.palette.m3outline;
                                default:
                                    return "#4bd97b";
                                }
                            }

                            width: ListView.view.width
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                Layout.alignment: Qt.AlignTop
                                text: {
                                    switch (checkRow.modelData.status) {
                                    case "fail":
                                        return "error";
                                    case "warn":
                                        return "warning";
                                    case "info":
                                        return "info";
                                    default:
                                        return "check_circle";
                                    }
                                }
                                fill: 1
                                color: checkRow.statusColour
                            }

                            Column {
                                Layout.fillWidth: true

                                StyledText {
                                    width: parent.width
                                    text: checkRow.modelData.name
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                    wrapMode: Text.WordWrap
                                }

                                StyledText {
                                    width: parent.width
                                    text: checkRow.modelData.detail
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.body.small
                                    wrapMode: Text.WordWrap
                                }
                            }

                            TextButton {
                                Layout.alignment: Qt.AlignVCenter
                                visible: !!checkRow.modelData.fix
                                text: SystemCheck.busyId === checkRow.modelData.id ? qsTr("Working…") : (checkRow.modelData.fix?.label ?? "")
                                type: TextButton.Tonal
                                disabled: SystemCheck.busyId !== ""
                                onClicked: SystemCheck.requestFix(checkRow.modelData.id)
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: scanList.count === 0
                            text: SystemCheck.scanning ? qsTr("Scanning…") : qsTr("Press Rescan to check the system")
                            color: Colours.palette.m3outline
                            font: Tokens.font.body.medium
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: qsTr("Reload shell")
                        type: TextButton.Tonal
                        onClicked: Quickshell.reload(false)
                    }

                    TextButton {
                        text: qsTr("Hard reload")
                        type: TextButton.Tonal
                        onClicked: Quickshell.reload(true)
                    }

                    TextButton {
                        text: qsTr("Run GC")
                        type: TextButton.Tonal
                        onClicked: gc()
                    }

                    TextButton {
                        text: qsTr("Copy diagnostics")
                        type: TextButton.Tonal
                        onClicked: DebugConsole.copyDiagnostics()
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: qsTr("qs ipc call debug toggle")
                        color: Colours.palette.m3outline
                        font: Tokens.font.mono.small
                    }
                }
            }

            // Fix card, three states: confirmation (exact commands before
            // anything runs), live progress (every output line as it
            // happens), and the final result with the full log
            Rectangle {
                anchors.fill: parent
                visible: SystemCheck.pendingFix !== null || SystemCheck.busyId !== "" || SystemCheck.fixResult !== null
                color: Qt.alpha(Colours.palette.m3scrim, 0.5)

                MouseArea {
                    anchors.fill: parent
                    onClicked: SystemCheck.cancelPendingFix()
                }

                StyledRect {
                    anchors.centerIn: parent
                    width: Math.min(640, parent.width - Tokens.padding.large * 4)
                    implicitHeight: confirmContent.implicitHeight + Tokens.padding.large * 2

                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                    MouseArea {
                        anchors.fill: parent
                    }

                    ColumnLayout {
                        id: confirmContent

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: SystemCheck.pendingFix?.title ?? (SystemCheck.busyId !== "" ? qsTr("Running fix — live output") : SystemCheck.fixResult?.success ? qsTr("Fix finished") : qsTr("Fix failed — the log shows where it stopped"))
                            color: SystemCheck.fixResult && !SystemCheck.fixResult.success ? "#ff5c5c" : Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: SystemCheck.pendingFix !== null
                            text: SystemCheck.pendingFix?.summary ?? ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.medium
                            wrapMode: Text.WordWrap
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            visible: SystemCheck.pendingFix !== null
                            implicitHeight: cmdList.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surface

                            Column {
                                id: cmdList

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.extraSmall

                                Repeater {
                                    model: SystemCheck.pendingFix?.commands ?? []

                                    StyledText {
                                        required property string modelData

                                        width: parent.width
                                        text: modelData
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.mono.small
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                            }
                        }

                        // Live output while the fix runs, full log afterwards
                        StyledClippingRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 240
                            visible: SystemCheck.pendingFix === null
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surface

                            StyledListView {
                                id: fixLogView

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                clip: true
                                model: SystemCheck.fixLog
                                spacing: 1

                                onCountChanged: Qt.callLater(() => fixLogView.positionViewAtEnd())

                                StyledScrollBar.vertical: StyledScrollBar {
                                    flickable: fixLogView
                                }

                                delegate: StyledText {
                                    required property string line

                                    width: ListView.view.width
                                    text: line
                                    color: line.startsWith("FAIL") ? "#ff5c5c" : line.startsWith("WARN") ? "#ffc233" : line.startsWith("OK") ? "#4bd97b" : line.startsWith("==>") ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                    font: Tokens.font.mono.small
                                    wrapMode: Text.WrapAnywhere
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: fixLogView.count === 0
                                    // A fix that produced no output must still report
                                    // its ending — without this the label reads
                                    // "Starting…" forever after a silent fix finishes
                                    text: {
                                        if (SystemCheck.fixResult !== null)
                                            return SystemCheck.fixResult.success ? qsTr("Done — the fix finished with no output") : qsTr("Failed (code %1) — no output produced").arg(SystemCheck.fixResult.code);
                                        return SystemCheck.runningFixRoot ? qsTr("Waiting for the password prompt…") : qsTr("Starting…");
                                    }
                                    color: SystemCheck.fixResult === null ? Colours.palette.m3outline : SystemCheck.fixResult.success ? "#4bd97b" : "#ff5c5c"
                                    font: Tokens.font.body.medium
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: SystemCheck.pendingFix !== null && (SystemCheck.pendingFix?.root ?? false)
                            text: qsTr("Runs as root — pkexec will ask for your password.")
                            color: "#ffc233"
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: SystemCheck.pendingFix !== null && (SystemCheck.pendingFix?.root ?? false) && SystemCheck.polkitAgentMissing
                            text: qsTr("No polkit agent is running — the password prompt cannot appear and this fix would hang. Fix the polkit agent finding first.")
                            color: "#ff5c5c"
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            Item {
                                Layout.fillWidth: true
                            }

                            TextButton {
                                visible: SystemCheck.pendingFix !== null
                                text: qsTr("Cancel")
                                type: TextButton.Text
                                onClicked: SystemCheck.cancelPendingFix()
                            }

                            TextButton {
                                visible: SystemCheck.pendingFix !== null
                                text: qsTr("Confirm & run")
                                onClicked: SystemCheck.confirmPendingFix()
                            }

                            TextButton {
                                visible: SystemCheck.pendingFix === null && SystemCheck.fixLog.count > 0
                                text: qsTr("Copy log")
                                type: TextButton.Tonal
                                onClicked: SystemCheck.copyFixLog()
                            }

                            TextButton {
                                visible: SystemCheck.busyId !== ""
                                text: qsTr("Cancel fix")
                                type: TextButton.Tonal
                                onClicked: SystemCheck.cancelRunningFix()
                            }

                            TextButton {
                                visible: SystemCheck.busyId === "" && SystemCheck.fixResult !== null
                                text: qsTr("Close")
                                onClicked: SystemCheck.dismissFixResult()
                            }
                        }
                    }
                }
            }
        }
    }
}
