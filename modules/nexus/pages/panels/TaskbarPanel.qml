pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Appearance
        SectionHeader {
            first: true
            text: qsTr("Appearance")
        }

        ToggleRow {
            first: true
            text: qsTr("Show logo")
            checked: ShellPrefs.barLogoShow
            onToggled: ShellPrefs.setBarLogoShow(checked)
        }

        ToggleRow {
            text: qsTr("Logo as edge endcap")
            subtext: qsTr("On: oversized logo caps the pill's left end. Off: regular logo inside the fully rounded pill")
            checked: ShellPrefs.barLogoEndcap
            enabled: ShellPrefs.barLogoShow
            onToggled: ShellPrefs.setBarLogoEndcap(checked)
        }

        StepperRow {
            label: qsTr("Logo size")
            subtext: qsTr("Percent of the default size")
            value: Math.round(ShellPrefs.barLogoScale * 100)
            from: 50
            to: 200
            stepSize: 10
            enabled: ShellPrefs.barLogoShow
            onMoved: v => ShellPrefs.setBarLogoScale(v / 100)
        }

        StepperRow {
            label: qsTr("Logo offset X")
            subtext: qsTr("Pixels rightward; endcap style only")
            value: ShellPrefs.barLogoOffsetX
            from: -20
            to: 80
            enabled: ShellPrefs.barLogoShow && ShellPrefs.barLogoEndcap
            onMoved: v => ShellPrefs.setBarLogoOffsetX(v)
        }

        StepperRow {
            label: qsTr("Logo offset Y")
            subtext: qsTr("Pixels upward; endcap style only")
            value: ShellPrefs.barLogoOffsetY
            from: -20
            to: 20
            enabled: ShellPrefs.barLogoShow && ShellPrefs.barLogoEndcap
            onMoved: v => ShellPrefs.setBarLogoOffsetY(v)
        }

        TextRow {
            label: qsTr("Custom logo image")
            subtext: qsTr("Path to an svg/png tinted with the accent colour; empty for the distro logo")
            placeholder: qsTr("/path/to/logo.svg")
            value: ShellPrefs.barLogoSource
            onCommitted: v => ShellPrefs.setBarLogoSource(v)
        }

        ToggleRow {
            last: true
            text: qsTr("Active window readout")
            subtext: qsTr("Show the focused window's title in the bar (needs an activeWindow entry in the bar config)")
            checked: ShellPrefs.barShowActiveWindow
            onToggled: ShellPrefs.setBarShowActiveWindow(checked)
        }

        // Behaviour
        SectionHeader {
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: qsTr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            label: qsTr("Workspaces")
            status: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            icon: "web_asset"
            label: qsTr("Active window")
            status: qsTr("Title display, popout")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "widgets"
            label: qsTr("Tray")
            status: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "signal_cellular_alt"
            label: qsTr("Status icons")
            status: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            last: true
            icon: "schedule"
            label: qsTr("Clock")
            status: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(9)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            checked: Config.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Scroll on the bottom half of the bar to adjust brightness")
            checked: Config.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
