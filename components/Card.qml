import QtQuick
import Caelestia.Config
import qs.services

// Dashboard-style nested card: translucent shell with a hairline border and
// an inset surface. Hovering brightens the border towards the accent.
// Content declared inside an instance paints above the inset surface.
StyledRect {
    id: root

    property bool hoverable: true

    color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.7)
    border.width: 1
    border.color: hover.hovered ? Qt.alpha(Colours.palette.m3primary, 0.35) : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
    radius: Tokens.rounding.extraLarge

    Behavior on border.color {
        CAnim {}
    }

    HoverHandler {
        id: hover

        enabled: root.hoverable
    }

    StyledRect {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        radius: Math.max(0, root.radius - anchors.margins)
        color: Colours.tPalette.m3surfaceContainer
    }
}
