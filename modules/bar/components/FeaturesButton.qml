pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Bar wrench: opens the feature-mode menu. Lights up (filled, primary) while
// any mode is active and shows a count badge, so an armed mode is never
// invisible.
Item {
    id: root

    readonly property int active: Features.activeCount

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    StateLayer {
        id: stateLayer

        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        onClicked: Features.menuOpen = !Features.menuOpen
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "build"
        // Distance-field rendering: native glyph rasters blur under the
        // hover scale-up; QtRendering stays crisp at any scale.
        renderType: Text.QtRendering
        color: root.active > 0 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        fill: root.active > 0 || Features.menuOpen ? 1 : 0
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
    }

    // Active-mode count badge.
    StyledRect {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -Tokens.padding.extraSmall / 2
        anchors.topMargin: -Tokens.padding.extraSmall / 2

        implicitWidth: Math.max(count.implicitWidth + Tokens.padding.extraSmall, count.implicitHeight)
        implicitHeight: count.implicitHeight

        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        scale: root.active > 0 ? 1 : 0
        visible: scale > 0

        StyledText {
            id: count

            anchors.centerIn: parent
            text: root.active
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
