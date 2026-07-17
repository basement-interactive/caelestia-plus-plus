pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string newBindKind: "exec"

    title: qsTr("Keybinds")
    isSubPage: true

    // [knob, label] pairs per section; values are HyprMod bind strings
    // like "SUPER + SHIFT" or "SUPER + T". Applied on compositor reload.
    readonly property var sections: [
        {
            title: qsTr("Workspaces"),
            binds: [["kbGoToWs", qsTr("Go to workspace")], ["kbGoToWsGroup", qsTr("Go to workspace group")], ["kbMoveWinToWs", qsTr("Move window to workspace")], ["kbMoveWinToWsGroup", qsTr("Move window to workspace group")], ["kbNextWs", qsTr("Next workspace")], ["kbPrevWs", qsTr("Previous workspace")]]
        },
        {
            title: qsTr("Windows"),
            binds: [["kbMoveWindow", qsTr("Move window")], ["kbResizeWindow", qsTr("Resize window")], ["kbCloseWindow", qsTr("Close window")], ["kbWindowFullscreen", qsTr("Fullscreen")], ["kbWindowBorderedFullscreen", qsTr("Bordered fullscreen")], ["kbToggleWindowFloating", qsTr("Toggle floating")], ["kbPinWindow", qsTr("Pin window")], ["kbWindowPip", qsTr("Picture in picture")]]
        },
        {
            title: qsTr("Window groups"),
            binds: [["kbToggleGroup", qsTr("Toggle group")], ["kbUngroup", qsTr("Ungroup")], ["kbWindowGroupCycleNext", qsTr("Cycle next in group")], ["kbWindowGroupCyclePrev", qsTr("Cycle previous in group")]]
        },
        {
            title: qsTr("Special workspaces"),
            binds: [["kbSpecialWs", qsTr("Special workspace")], ["kbSystemMonitorWs", qsTr("System monitor")], ["kbMusicWs", qsTr("Music")], ["kbCommunicationWs", qsTr("Communication")], ["kbTodoWs", qsTr("Todo")]]
        },
        {
            title: qsTr("Apps"),
            binds: [["kbTerminal", qsTr("Terminal")], ["kbBrowser", qsTr("Browser")], ["kbEditor", qsTr("Editor")], ["kbFileExplorer", qsTr("File explorer")]]
        },
        {
            title: qsTr("Shell"),
            binds: [["kbSession", qsTr("Session menu")], ["kbShowSidebar", qsTr("Sidebar")], ["kbShowPanels", qsTr("Panels")], ["kbClearNotifs", qsTr("Clear notifications")], ["kbLock", qsTr("Lock")], ["kbRestoreLock", qsTr("Restore lock")]]
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Custom keybinds")
        }

        Repeater {
            model: HyprMod.customBinds

            ConnectedRect {
                id: bindRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: false
                implicitHeight: bindLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: bindLayout

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    Column {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: bindRow.modelData.combo
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: (bindRow.modelData.kind === "exec" ? qsTr("Run: ") : bindRow.modelData.kind === "global" ? qsTr("Shell action: ") : qsTr("Lua: ")) + bindRow.modelData.value
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        icon: "delete"
                        onClicked: HyprMod.delBind(bindRow.index)
                    }
                }
            }
        }

        TextRow {
            id: newCombo

            first: HyprMod.customBinds.length === 0
            label: qsTr("Keys")
            placeholder: qsTr("e.g. SUPER + B")
        }

        SelectRow {
            id: newKind

            Layout.fillWidth: true
            label: qsTr("Action type")
            fallbackText: qsTr("Run command")
            menuItems: [execItem, globalItem, luaItem]
            onSelected: item => root.newBindKind = item === globalItem ? "global" : item === luaItem ? "lua" : "exec"

            MenuItem {
                id: execItem

                text: qsTr("Run command")
            }

            MenuItem {
                id: globalItem

                text: qsTr("Shell action (IPC global)")
            }

            MenuItem {
                id: luaItem

                text: qsTr("Raw lua")
            }
        }

        TextRow {
            id: newValue

            label: qsTr("Action")
            placeholder: root.newBindKind === "exec" ? qsTr("e.g. firefox") : root.newBindKind === "global" ? qsTr("e.g. caelestia:launcher") : qsTr("e.g. hl.dsp.togglefloating()")
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: addButton.implicitHeight + Tokens.padding.medium * 2

            IconTextButton {
                id: addButton

                anchors.centerIn: parent
                icon: "add"
                text: qsTr("Add keybind")
                font: Tokens.font.body.large
                isRound: true
                type: IconTextButton.Tonal
                disabled: !newCombo.fieldText.length || !newValue.fieldText.length
                onClicked: {
                    HyprMod.addBind(newCombo.fieldText, root.newBindKind, newValue.fieldText, "");
                    newCombo.value = "";
                    newValue.value = "";
                }
            }
        }

        Repeater {
            model: root.sections

            ColumnLayout {
                id: section

                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: section.modelData.title
                }

                Repeater {
                    model: section.modelData.binds

                    TextRow {
                        required property var modelData
                        required property int index

                        first: index === 0
                        last: index === section.modelData.binds.length - 1
                        label: modelData[1]
                        placeholder: qsTr("e.g. SUPER + T")
                        value: HyprMod.get(modelData[0], "")
                        onCommitted: v => HyprMod.set(modelData[0], v)
                    }
                }
            }
        }
    }
}
