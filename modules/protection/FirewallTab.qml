pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Firewall tab: the redwall per-app outbound firewall rules, re-homed from the
// old standalone FirewallPanel into the tabbed security center.
ColumnLayout {
    id: root

    readonly property int allowCount: Firewall.rules.filter(r => r.action === "allow").length
    readonly property int denyCount: Firewall.rules.length - allowCount

    spacing: Tokens.spacing.medium

    TabHeader {
        Layout.fillWidth: true
        icon: Firewall.connected ? "gpp_good" : "gpp_bad"
        title: qsTr("Firewall")
        accent: Firewall.connected && Firewall.enabled ? Colours.palette.m3primary : Colours.palette.m3outline
        subtitle: !Firewall.connected ? qsTr("Daemon not running") : !Firewall.enabled ? qsTr("Disabled — all traffic allowed") : qsTr("%1 allowed · %2 denied").arg(root.allowCount).arg(root.denyCount)
        subtitleError: !Firewall.connected || !Firewall.enabled
        showSwitch: Firewall.connected
        switchOn: Firewall.enabled
        onToggled: Firewall.setEnabled(!Firewall.enabled)
    }

    StyledText {
        Layout.fillWidth: true
        visible: !Firewall.connected
        text: qsTr("Enable the Firewall from the Protection tab, or install it with system/redwall/install.sh, to start filtering outbound connections per-app.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: Firewall.connected
        clip: true
        contentHeight: mgr.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: parent
        }

        RuleManager {
            id: mgr
            width: parent.width
            rules: Firewall.rules
            positiveAction: "allow"
            negativeAction: "deny"
            positiveLabel: qsTr("Allow")
            negativeLabel: qsTr("Deny")
            emptyText: qsTr("No rules yet. Apps you allow or deny will show up here.")
            onSetRule: (exe, action, name) => Firewall.setRule(exe, action, name)
            onDelRule: exe => Firewall.delRule(exe)
        }
    }
}
