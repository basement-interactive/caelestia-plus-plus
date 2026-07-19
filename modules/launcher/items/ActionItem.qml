import QtQuick
import Caelestia.Config
import qs.components
import qs.services

LauncherItem {
    id: root

    required property var modelData

    onTriggered: modelData?.onClicked(list)

    Tile {
        id: tile

        icon: root.modelData?.icon ?? ""
    }

    Column {
        anchors.left: tile.right
        anchors.leftMargin: Tokens.spacing.medium
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.modelData?.name ?? ""
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.modelData?.desc ?? ""
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }
}
