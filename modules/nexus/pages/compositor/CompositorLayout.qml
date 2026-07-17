import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Layout & gaps")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Gaps")
        }

        StepperRow {
            first: true
            label: qsTr("Between windows")
            value: HyprMod.get("windowGapsIn", 5)
            from: 0
            to: 50
            onMoved: v => HyprMod.set("windowGapsIn", v)
        }

        StepperRow {
            label: qsTr("Screen edges")
            value: HyprMod.get("windowGapsOut", 10)
            from: 0
            to: 50
            onMoved: v => HyprMod.set("windowGapsOut", v)
        }

        StepperRow {
            label: qsTr("Screen edges, single window")
            subtext: qsTr("Applies on compositor reload")
            value: HyprMod.get("singleWindowGapsOut", 20)
            from: 0
            to: 60
            onMoved: v => HyprMod.set("singleWindowGapsOut", v)
        }

        StepperRow {
            last: true
            label: qsTr("Between workspaces")
            subtext: qsTr("Gap when sliding between workspaces")
            value: HyprMod.get("workspaceGaps", 20)
            from: 0
            to: 100
            onMoved: v => HyprMod.set("workspaceGaps", v)
        }
    }
}
