import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

LauncherItem {
    id: root

    required property M3Variants.Variant modelData

    onTriggered: modelData?.onClicked(list)

    Tile {
        id: tile

        icon: root.modelData?.icon ?? ""
    }

    Column {
        anchors.left: tile.right
        anchors.leftMargin: Tokens.spacing.medium
        anchors.right: parent.right
        anchors.rightMargin: current.visible ? current.implicitWidth + Tokens.spacing.medium : 0
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.modelData?.name ?? ""
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.modelData?.description ?? ""
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }

    MaterialIcon {
        id: current

        visible: root.modelData?.variant === Schemes.currentVariant
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: "check"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.large
    }
}
