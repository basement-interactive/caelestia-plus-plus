pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Overview: one status card per subsystem, each showing a live state pill and a
// one-line detail, and drilling into that subsystem's tab on click. The overall
// posture lives in the hero band above (SecurityCenter), so this is the
// actionable breakdown beneath it.
Item {
    id: root

    readonly property color good: "#4bd97b"
    readonly property color warn: "#ffc233"
    readonly property color bad: "#ff5c5c"

    Component.onCompleted: if (!Startup.entries.length) Startup.refresh()

    StyledFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: cards.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: parent
        }

        ColumnLayout {
            id: cards
            width: parent.width
            spacing: Tokens.spacing.medium

            AreaCard {
                Layout.fillWidth: true
                icon: Protection.connected ? "security" : "gpp_maybe"
                title: qsTr("Protection")
                status: !Protection.connected ? qsTr("Not set up") : Protection.enabled ? qsTr("Active") : qsTr("Off")
                statusColour: !Protection.connected ? root.warn : Protection.enabled ? root.good : root.warn
                detail: !Protection.connected ? qsTr("Turn on behavioral monitoring for exploit payloads") : Protection.enabled ? qsTr("Watching process behavior · %1 rules").arg(Protection.rules.length) : qsTr("Monitoring is paused — nothing is watched")
                onClicked: Security.tab = "protection"
            }

            AreaCard {
                Layout.fillWidth: true
                icon: Firewall.connected ? "gpp_good" : "gpp_bad"
                title: qsTr("Firewall")
                status: !Firewall.connected ? qsTr("Not running") : Firewall.enabled ? qsTr("On") : qsTr("Off")
                statusColour: !Firewall.connected ? root.warn : Firewall.enabled ? root.good : root.warn
                detail: !Firewall.connected ? qsTr("Install to filter outbound connections per-app") : Firewall.enabled ? qsTr("%1 allowed · %2 denied").arg(Firewall.rules.filter(r => r.action === "allow").length).arg(Firewall.rules.filter(r => r.action !== "allow").length) : qsTr("Disabled — all traffic is allowed")
                onClicked: Security.tab = "firewall"
            }

            AreaCard {
                Layout.fillWidth: true
                icon: "travel_explore"
                title: qsTr("HTTP Debugger")
                status: !Http.installed ? qsTr("Not set up") : Http.running ? qsTr("Capturing") : qsTr("Off")
                statusColour: !Http.installed ? root.warn : Http.running ? root.good : Colours.palette.m3outline
                detail: !Http.installed ? qsTr("Install to inspect, resend, intercept and modify traffic") : Http.running ? qsTr("Proxy on 127.0.0.1:%1 · %2 flows").arg(Http.port).arg(Http.flows.length) : qsTr("Inspect, resend, intercept and modify HTTP/HTTPS")
                onClicked: Security.tab = "http"
            }

            AreaCard {
                Layout.fillWidth: true
                icon: "rocket_launch"
                title: qsTr("Startup Apps")
                status: Startup.scanning ? qsTr("…") : qsTr("%1").arg(Startup.entries.filter(e => e.enabled).length)
                statusColour: Colours.palette.m3primary
                detail: qsTr("Programs and services that launch at login")
                onClicked: Security.tab = "startup"
            }
        }
    }

    component AreaCard: StyledRect {
        id: acard

        property string icon
        property string title
        property string status
        property color statusColour
        property string detail

        signal clicked

        implicitHeight: cardRow.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Qt.alpha(acard.statusColour, 0.3)
        scale: cardLayer.pressed ? 0.99 : 1

        Behavior on scale {
            Anim {
                type: cardLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
            }
        }

        StateLayer {
            id: cardLayer
            radius: parent.radius
            onClicked: acard.clicked()
        }

        RowLayout {
            id: cardRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: implicitHeight
                implicitHeight: areaIcon.implicitHeight + Tokens.padding.medium
                radius: Tokens.rounding.full
                color: Qt.alpha(acard.statusColour, 0.15)

                MaterialIcon {
                    id: areaIcon
                    anchors.centerIn: parent
                    text: acard.icon
                    fill: 1
                    color: acard.statusColour
                    fontStyle: Tokens.font.icon.large
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                StyledText {
                    text: acard.title
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                }

                StyledText {
                    width: parent.width
                    text: acard.detail
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }

            // Status pill.
            StyledRect {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: statusText.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: statusText.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.full
                color: Qt.alpha(acard.statusColour, 0.18)

                StyledText {
                    id: statusText
                    anchors.centerIn: parent
                    text: acard.status
                    color: acard.statusColour
                    font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                }
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "chevron_right"
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
