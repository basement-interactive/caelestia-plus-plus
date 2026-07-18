pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Hidden debug console, opened by 10 rapid clicks on the bar clock. Live
// log tail with level filters and search, plus shell diagnostics and a few
// maintenance actions. Dismiss: click the scrim or press Escape.
Scope {
    id: root

    readonly property bool open: DebugConsole.open
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

    StyledWindow {
        id: win

        screen: root.focusedScreen
        name: "debug-console"
        visible: root.open || closeTimer.running

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Timer {
            id: closeTimer
            interval: Tokens.anim.durations.large
        }

        Connections {
            target: root
            function onOpenChanged(): void {
                if (!root.open)
                    closeTimer.restart();
            }
        }

        StyledRect {
            anchors.fill: parent
            color: Colours.palette.m3scrim
            opacity: root.open ? 0.25 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: DebugConsole.open = false
            }
        }

        StyledRect {
            id: card

            anchors.centerIn: parent
            implicitWidth: Math.min(940, win.width - Tokens.padding.large * 4)
            implicitHeight: Math.min(660, win.height - Tokens.padding.large * 4)

            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.96
            focus: root.open

            Keys.onEscapePressed: DebugConsole.open = false

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.Emphasized
                }
            }

            StyledClippingRect {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small

                radius: card.radius - Tokens.padding.small
                color: Colours.palette.m3surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

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

                            StyledText {
                                text: qsTr("PID %1  ·  %2 RSS  ·  %3 warnings  ·  %4 errors").arg(Quickshell.processId).arg(DebugConsole.memUsage).arg(DebugConsole.warnCount).arg(DebugConsole.errorCount)
                                color: DebugConsole.errorCount > 0 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
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
                                    const levelColour = {
                                        error: Colours.palette.m3error,
                                        warn: Colours.palette.m3tertiary,
                                        debug: Colours.palette.m3outline
                                    }[entry.level] ?? Colours.palette.m3onSurfaceVariant;
                                    const messageColour = entry.level === "error" ? Colours.palette.m3error : Colours.palette.m3onSurface;
                                    return `<span style="color:${Colours.palette.m3outline}">${entry.time}</span> <span style="color:${levelColour}">${entry.level.toUpperCase()}</span> <span style="color:${Colours.palette.m3secondary}">${esc(entry.category)}</span> <span style="color:${messageColour}">${esc(entry.message)}</span>`;
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
}
