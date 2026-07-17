import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Input & gestures")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Touchpad")
        }

        ToggleRow {
            first: true
            text: qsTr("Disable while typing")
            checked: HyprMod.get("touchpadDisableTyping", true)
            onToggled: HyprMod.set("touchpadDisableTyping", checked)
        }

        SliderRow {
            last: true
            icon: "swipe_vertical"
            label: qsTr("Scroll speed")
            valueLabel: HyprMod.get("touchpadScrollFactor", 0.3).toFixed(2)
            value: HyprMod.get("touchpadScrollFactor", 0.3)
            onMoved: v => HyprMod.set("touchpadScrollFactor", Math.max(0.05, Math.round(v * 20) / 20))
        }

        SectionHeader {
            text: qsTr("Gestures")
        }

        StepperRow {
            first: true
            label: qsTr("Gesture fingers")
            subtext: qsTr("Special workspace and window gestures; applies on reload")
            value: HyprMod.get("gestureFingers", 3)
            from: 3
            to: 5
            onMoved: v => HyprMod.set("gestureFingers", v)
        }

        StepperRow {
            label: qsTr("Workspace swipe fingers")
            subtext: qsTr("Applies on compositor reload")
            value: HyprMod.get("workspaceSwipeFingers", 4)
            from: 3
            to: 5
            onMoved: v => HyprMod.set("workspaceSwipeFingers", v)
        }

        StepperRow {
            last: true
            label: qsTr("Sleep gesture fingers")
            subtext: qsTr("Swipe down to sleep; applies on reload")
            value: HyprMod.get("gestureFingersMore", 4)
            from: 3
            to: 5
            onMoved: v => HyprMod.set("gestureFingersMore", v)
        }
    }
}
