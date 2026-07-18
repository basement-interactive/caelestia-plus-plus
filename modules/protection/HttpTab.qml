pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// HTTP Debugger tab — placeholder. The real implementation (a mitmproxy-backed
// intercept/modify/resend/block flow list, with a local CA for HTTPS) lands in
// the next round; kept here so the tab strip shows the full plan.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    TabHeader {
        Layout.fillWidth: true
        icon: "travel_explore"
        title: qsTr("HTTP Debugger")
        subtitle: qsTr("Coming next")
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.padding.large * 2, 420)
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "construction"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.large.scale(2).build()
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Inspect, intercept, modify, resend and block HTTP/HTTPS traffic")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("A mitmproxy-backed debugger with a local CA for HTTPS. Landing in the next update — it plays nicely with your VPN via an explicit app proxy.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
