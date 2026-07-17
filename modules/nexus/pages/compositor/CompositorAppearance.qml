import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Appearance")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Blur")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            subtext: qsTr("Blur behind translucent windows (auto-off on battery)")
            checked: HyprMod.get("blurEnabled", false)
            onToggled: HyprMod.set("blurEnabled", checked)
        }

        ToggleRow {
            text: qsTr("Blur popups")
            checked: HyprMod.get("blurPopups", false)
            enabled: HyprMod.get("blurEnabled", false)
            onToggled: HyprMod.set("blurPopups", checked)
        }

        ToggleRow {
            text: qsTr("Blur input methods")
            checked: HyprMod.get("blurInputMethods", false)
            enabled: HyprMod.get("blurEnabled", false)
            onToggled: HyprMod.set("blurInputMethods", checked)
        }

        ToggleRow {
            text: qsTr("Blur special workspace")
            checked: HyprMod.get("blurSpecialWs", false)
            enabled: HyprMod.get("blurEnabled", false)
            onToggled: HyprMod.set("blurSpecialWs", checked)
        }

        ToggleRow {
            text: qsTr("X-ray")
            subtext: qsTr("Blur only what is directly beneath — cheaper, less accurate")
            checked: HyprMod.get("blurXray", false)
            enabled: HyprMod.get("blurEnabled", false)
            onToggled: HyprMod.set("blurXray", checked)
        }

        StepperRow {
            label: qsTr("Size")
            value: HyprMod.get("blurSize", 5)
            from: 1
            to: 15
            enabled: HyprMod.get("blurEnabled", false)
            onMoved: v => HyprMod.set("blurSize", v)
        }

        StepperRow {
            last: true
            label: qsTr("Passes")
            subtext: qsTr("More passes = smoother and more expensive")
            value: HyprMod.get("blurPasses", 2)
            from: 1
            to: 6
            enabled: HyprMod.get("blurEnabled", false)
            onMoved: v => HyprMod.set("blurPasses", v)
        }

        SectionHeader {
            text: qsTr("Shadows")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: HyprMod.get("shadowEnabled", false)
            onToggled: HyprMod.set("shadowEnabled", checked)
        }

        StepperRow {
            label: qsTr("Range")
            value: HyprMod.get("shadowRange", 15)
            from: 0
            to: 40
            enabled: HyprMod.get("shadowEnabled", false)
            onMoved: v => HyprMod.set("shadowRange", v)
        }

        StepperRow {
            last: true
            label: qsTr("Render power")
            subtext: qsTr("Falloff sharpness")
            value: HyprMod.get("shadowRenderPower", 4)
            from: 1
            to: 4
            enabled: HyprMod.get("shadowEnabled", false)
            onMoved: v => HyprMod.set("shadowRenderPower", v)
        }

        SectionHeader {
            text: qsTr("Windows")
        }

        StepperRow {
            first: true
            label: qsTr("Corner rounding")
            value: HyprMod.get("windowRounding", 15)
            from: 0
            to: 30
            onMoved: v => HyprMod.set("windowRounding", v)
        }

        StepperRow {
            label: qsTr("Opacity")
            subtext: qsTr("Percent; applies on compositor reload")
            value: Math.round(HyprMod.get("windowOpacity", 1) * 100)
            from: 50
            to: 100
            onMoved: v => HyprMod.set("windowOpacity", v / 100)
        }

        StepperRow {
            last: true
            label: qsTr("Border size")
            value: HyprMod.get("windowBorderSize", 2)
            from: 0
            to: 10
            onMoved: v => HyprMod.set("windowBorderSize", v)
        }
    }
}
