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

// Centered prompt shown once after startup when the system scan finds
// something the machine needs fixed on its own: packages the shell wants
// but lacks, or privileged root halves installed from an older Caelestia++.
// One "Fix now" runs everything through a single pkexec (one password);
// "Later" remembers the current set and stays quiet until something new
// appears. Details opens the debug window's scan tab.
Scope {
    id: root

    readonly property bool open: SystemCheck.promptOpen
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

    StyledWindow {
        id: win

        screen: root.focusedScreen
        name: "setup-prompt"
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
            opacity: root.open ? 0.35 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: SystemCheck.dismissPrompt()
            }
        }

        StyledRect {
            id: card

            anchors.centerIn: parent
            implicitWidth: 520
            implicitHeight: core.implicitHeight + Tokens.padding.small * 2

            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.92
            focus: root.open

            Keys.onEscapePressed: SystemCheck.dismissPrompt()

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
                id: core

                anchors.fill: parent
                anchors.margins: Tokens.padding.small

                implicitHeight: inner.implicitHeight
                radius: card.radius - Tokens.padding.small
                color: Colours.palette.m3surfaceContainerLow

                ColumnLayout {
                    id: inner

                    width: parent.width
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Tokens.padding.extraLargeIncreased
                        Layout.bottomMargin: 0
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "healing"
                            fill: 1
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large
                        }

                        Column {
                            Layout.fillWidth: true

                            StyledText {
                                text: qsTr("System needs attention")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                            }

                            StyledText {
                                text: qsTr("Caelestia++ works, but not at full function")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.extraLargeIncreased
                        Layout.rightMargin: Tokens.padding.extraLargeIncreased
                        spacing: Tokens.spacing.small
                        visible: SystemCheck.pendingFix === null

                        Repeater {
                            model: ScriptModel {
                                values: SystemCheck.promptItems
                            }

                            RowLayout {
                                id: row

                                required property var modelData

                                Layout.fillWidth: true
                                spacing: Tokens.spacing.medium

                                MaterialIcon {
                                    text: row.modelData.status === "fail" ? "error" : row.modelData.fixType === "roothalf" ? "upgrade" : "warning"
                                    color: row.modelData.status === "fail" ? "#ff5c5c" : "#ffc233"
                                }

                                Column {
                                    Layout.fillWidth: true

                                    StyledText {
                                        width: parent.width
                                        text: row.modelData.name
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: row.modelData.detail
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    // Confirmation view: replaces the item list once Fix now
                    // is pressed, showing the exact commands before anything
                    // runs
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.extraLargeIncreased
                        Layout.rightMargin: Tokens.padding.extraLargeIncreased
                        spacing: Tokens.spacing.small
                        visible: SystemCheck.pendingFix !== null

                        StyledText {
                            Layout.fillWidth: true
                            text: SystemCheck.pendingFix?.summary ?? ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.medium
                            wrapMode: Text.WordWrap
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: promptCmds.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surface

                            Column {
                                id: promptCmds

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

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Runs as root — pkexec will ask for your password.")
                            color: "#ffc233"
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Tokens.padding.extraLargeIncreased
                        Layout.topMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small
                        visible: SystemCheck.pendingFix === null

                        TextButton {
                            text: qsTr("Later")
                            type: TextButton.Text
                            onClicked: SystemCheck.dismissPrompt()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        TextButton {
                            text: qsTr("Details")
                            type: TextButton.Tonal
                            onClicked: {
                                SystemCheck.promptOpen = false;
                                DebugConsole.panelTab = "scan";
                                DebugConsole.open = true;
                            }
                        }

                        TextButton {
                            text: SystemCheck.busyId === "all" ? qsTr("Fixing…") : qsTr("Fix now")
                            disabled: SystemCheck.busyId !== ""
                            onClicked: SystemCheck.requestFixAll()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Tokens.padding.extraLargeIncreased
                        Layout.topMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small
                        visible: SystemCheck.pendingFix !== null

                        TextButton {
                            text: qsTr("Back")
                            type: TextButton.Text
                            onClicked: SystemCheck.cancelPendingFix()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        TextButton {
                            text: qsTr("Confirm & fix")
                            onClicked: {
                                SystemCheck.confirmPendingFix();
                                SystemCheck.dismissPrompt();
                            }
                        }
                    }
                }
            }
        }
    }
}
