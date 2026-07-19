import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Rounded icon well at the left edge of a launcher row. Set `icon` for a
// Material glyph, or place custom content (e.g. an IconImage) as children.
StyledRect {
    property alias icon: glyph.text
    property alias iconColor: glyph.color

    anchors.verticalCenter: parent?.verticalCenter

    implicitWidth: implicitHeight
    implicitHeight: parent?.height ?? 0

    radius: Tokens.rounding.medium
    color: Colours.tPalette.m3surfaceContainerHigh
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

    MaterialIcon {
        id: glyph

        anchors.centerIn: parent
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.large
    }
}
