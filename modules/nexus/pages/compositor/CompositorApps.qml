import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Default apps")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Launched by keybinds and gestures — applies on compositor reload")
        }

        TextRow {
            first: true
            label: qsTr("Terminal")
            value: HyprMod.get("terminal", "")
            onCommitted: v => HyprMod.set("terminal", v)
        }

        TextRow {
            label: qsTr("Browser")
            value: HyprMod.get("browser", "")
            onCommitted: v => HyprMod.set("browser", v)
        }

        TextRow {
            label: qsTr("Editor")
            value: HyprMod.get("editor", "")
            onCommitted: v => HyprMod.set("editor", v)
        }

        TextRow {
            label: qsTr("File explorer")
            value: HyprMod.get("fileExplorer", "")
            onCommitted: v => HyprMod.set("fileExplorer", v)
        }

        TextRow {
            last: true
            label: qsTr("Audio settings")
            value: HyprMod.get("audioSettings", "")
            onCommitted: v => HyprMod.set("audioSettings", v)
        }
    }
}
