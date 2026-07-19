import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

LauncherItem {
    id: root

    required property Schemes.Scheme modelData

    onTriggered: modelData?.onClicked(list)

    StyledRect {
        id: preview

        anchors.verticalCenter: parent.verticalCenter

        border.width: 1
        border.color: Qt.alpha(`#${root.modelData?.colours?.outline}`, 0.5)

        color: `#${root.modelData?.colours?.surface}`
        radius: Tokens.rounding.full
        implicitWidth: parent.height * 0.8
        implicitHeight: parent.height * 0.8

        Item {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right

            implicitWidth: parent.implicitWidth / 2
            clip: true

            StyledRect {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right

                implicitWidth: preview.implicitWidth
                color: `#${root.modelData?.colours?.primary}`
                radius: Tokens.rounding.full
            }
        }
    }

    Column {
        anchors.left: preview.right
        anchors.leftMargin: Tokens.spacing.medium
        anchors.right: parent.right
        anchors.rightMargin: current.visible ? current.implicitWidth + Tokens.spacing.medium : 0
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.modelData?.flavour ?? ""
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.modelData?.name ?? ""
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }

    MaterialIcon {
        id: current

        visible: `${root.modelData?.name} ${root.modelData?.flavour}` === Schemes.currentScheme
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: "check"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.large
    }
}
