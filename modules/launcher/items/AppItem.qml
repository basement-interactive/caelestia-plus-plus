import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

LauncherItem {
    id: root

    required property DesktopEntry modelData

    readonly property bool favourite: modelData ? Strings.testRegexList(GlobalConfig.launcher.favouriteApps, modelData.id) : false

    onTriggered: {
        Apps.launch(modelData);
        list.screenState.launcher = false;
    }

    Tile {
        id: tile

        IconImage {
            anchors.centerIn: parent
            asynchronous: true
            source: Quickshell.iconPath(root.modelData?.icon, "image-missing")
            implicitSize: Math.round(parent.height * 0.7)
        }
    }

    Column {
        anchors.left: tile.right
        anchors.leftMargin: Tokens.spacing.medium
        anchors.right: parent.right
        anchors.rightMargin: root.favourite ? favIcon.implicitWidth + Tokens.spacing.medium : 0
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.modelData?.name ?? ""
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: (root.modelData?.comment || root.modelData?.genericName || root.modelData?.name) ?? ""
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }

    MaterialIcon {
        id: favIcon

        visible: root.favourite
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: "favorite"
        fill: 1
        color: Colours.palette.m3primary
    }
}
