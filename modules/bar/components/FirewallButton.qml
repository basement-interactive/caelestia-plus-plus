pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Bar shield: opens the tabbed security center (Protection, Firewall, HTTP,
// Startup). Reflects both guards at once:
//   neither running -> dim struck shield
//   something frozen/pending -> red shield-with-! that pulses + count badge
//   both clear -> calm shield-with-check
Item {
    id: root

    readonly property bool connected: Firewall.connected || Protection.connected
    readonly property bool active: (Firewall.connected && Firewall.enabled) || (Protection.connected && Protection.enabled)
    readonly property int pending: Firewall.pendingCount + Protection.pendingCount

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    StateLayer {
        id: stateLayer

        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        // Open on whichever guard is asking; default to Protection otherwise.
        onClicked: Security.open(Firewall.pendingCount > 0 && Protection.pendingCount === 0 ? "firewall" : "protection")
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: !root.connected ? "gpp_bad" : !root.active ? "shield" : root.pending > 0 ? "gpp_maybe" : "gpp_good"
        // Distance-field rendering: native glyph rasters blur under the
        // hover scale-up; QtRendering stays crisp at any scale.
        renderType: Text.QtRendering
        color: !root.connected || !root.active ? Colours.palette.m3outline : Colours.palette.m3primary
        fill: root.active && (root.pending > 0 || Security.panelOpen) ? 1 : 0
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        scale: stateLayer.pressed ? 1.05 : stateLayer.containsMouse ? 1.2 : 1

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        // Attention pulse — only while something is actually waiting, so it is
        // never a standing idle animation.
        SequentialAnimation on opacity {
            running: root.pending > 0 && !stateLayer.containsMouse
            loops: Animation.Infinite
            alwaysRunToEnd: true

            Anim {
                to: 0.45
                duration: Tokens.anim.durations.large
                easing: Tokens.anim.standardAccel
            }
            Anim {
                to: 1
                duration: Tokens.anim.durations.large
                easing: Tokens.anim.standardDecel
            }
        }
    }

    // Count badge.
    StyledRect {
        id: badge

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -Tokens.padding.extraSmall / 2
        anchors.topMargin: -Tokens.padding.extraSmall / 2

        implicitWidth: Math.max(count.implicitWidth + Tokens.padding.extraSmall, count.implicitHeight)
        implicitHeight: count.implicitHeight

        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        scale: root.pending > 0 ? 1 : 0
        visible: scale > 0

        StyledText {
            id: count

            anchors.centerIn: parent
            text: root.pending
            color: Colours.palette.m3onPrimary
            font: Tokens.font.body.builders.small.scale(0.75).weight(Font.Bold).build()
        }

        Behavior on scale {
            Anim {
                type: Anim.EmphasizedSmall
            }
        }
    }
}
