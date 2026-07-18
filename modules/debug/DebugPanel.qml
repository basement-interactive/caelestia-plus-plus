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
                    placeholderText: qsTr("Filter by category or message")
                    onTextChanged: DebugConsole.query = text
                }

                StyledClippingRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surface

                    // Non-interactive so mouse drags select text in the
                    // TextEdit instead of flicking; scrolling is wheel +
                    // scrollbar only
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

                        WheelHandler {
                            target: null
                            onWheel: event => logView.scrollBy(event.angleDelta.y)
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
        }
    }
}
