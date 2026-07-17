import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("System")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Volume keys")
        }

        StepperRow {
            first: true
            label: qsTr("Volume step")
            subtext: qsTr("Percent per keypress; applies on reload")
            value: HyprMod.get("volumeStep", 10)
            from: 1
            to: 25
            onMoved: v => HyprMod.set("volumeStep", v)
        }

        StepperRow {
            last: true
            label: qsTr("Volume limit")
            subtext: qsTr("Maximum volume percent")
            value: HyprMod.get("volumeMax", 100)
            from: 100
            to: 150
            stepSize: 10
            onMoved: v => HyprMod.set("volumeMax", v)
        }

        SectionHeader {
            text: qsTr("Cursor")
        }

        TextRow {
            first: true
            label: qsTr("Theme")
            value: HyprMod.get("cursorTheme", "")
            onCommitted: v => HyprMod.set("cursorTheme", v)
        }

        StepperRow {
            last: true
            label: qsTr("Size")
            value: HyprMod.get("cursorSize", 24)
            from: 16
            to: 48
            stepSize: 4
            onMoved: v => HyprMod.set("cursorSize", v)
        }

        SectionHeader {
            text: qsTr("Power")
        }

        TextRow {
            first: true
            last: true
            label: qsTr("Sleep gesture command")
            subtext: qsTr("Run on the sleep swipe gesture")
            value: HyprMod.get("sleepGestureCmd", "")
            onCommitted: v => HyprMod.set("sleepGestureCmd", v)
        }
    }
}
