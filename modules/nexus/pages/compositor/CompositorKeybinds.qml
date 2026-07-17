pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

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
