pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Protection tab: redguard's behavioral monitoring. When the daemon is not yet
// installed it offers a one-click (pkexec) install; once running it exposes the
// master switch and the per-executable allow/block rules.
ColumnLayout {
    id: root

    readonly property int allowCount: Protection.rules.filter(r => r.action === "allow").length
    readonly property int blockCount: Protection.rules.length - allowCount

    spacing: Tokens.spacing.medium

    TabHeader {
        Layout.fillWidth: true
        icon: Protection.connected ? "security" : "gpp_maybe"
        title: qsTr("Protection")
        accent: Protection.connected && Protection.enabled ? Colours.palette.m3primary : Colours.palette.m3outline
        subtitle: !Protection.connected ? qsTr("Not running") : !Protection.enabled ? qsTr("Disabled — nothing is monitored") : qsTr("Watching for suspicious behavior · %1 allowed · %2 blocked").arg(root.allowCount).arg(root.blockCount)
        subtitleError: Protection.connected && !Protection.enabled
        showSwitch: Protection.connected
        switchOn: Protection.enabled
        onToggled: Protection.setEnabled(!Protection.enabled)
    }

    // What it watches for — set expectations honestly.
    StyledText {
        Layout.fillWidth: true
        visible: Protection.connected
        text: qsTr("Freezes and asks before a process can act like an exploit payload: a shell wired to a network socket (reverse shell), or a binary run from a temp dir or deleted while running (dropper / in-memory malware). Decisions are remembered per app.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    // Not installed: the install affordance.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.large
        visible: !Protection.connected
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Protection watches process behavior and freezes anything that looks like a remote-code-execution payload, then asks you what to do. It runs a small privileged daemon and touches no networking, so it works the same with a VPN on.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            wrapMode: Text.WordWrap
        }

        TextButton {
            Layout.alignment: Qt.AlignLeft
            text: Protection.installing ? qsTr("Installing…") : qsTr("Enable Protection")
            disabled: Protection.installing
            // Close the center first: it's an overlay layer and would sit on
            // top of the polkit password prompt. Progress shows via toasts, and
            // the shield/overview attach live once the daemon starts.
            onClicked: {
                Protection.install();
                Security.panelOpen = false;
            }
        }
    }

    RuleManager {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: Protection.connected
        rules: Protection.rules
        positiveAction: "allow"
        negativeAction: "block"
        positiveLabel: qsTr("Allow")
        negativeLabel: qsTr("Block")
        positiveTitle: qsTr("Trusted")
        negativeTitle: qsTr("Blocked")
        positiveIcon: "verified_user"
        negativeIcon: "dangerous"
        emptyText: qsTr("No decisions yet. When a process is frozen and you choose Allow always or Block, it lands here.")
        onSetRule: (exe, action, name) => Protection.setRule(exe, action, name)
        onDelRule: exe => Protection.delRule(exe)
    }
}
