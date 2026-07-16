import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    StateLayer {
        id: stateLayer

        // Cursed workaround to make the height larger than the parent
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        onClicked: root.screenState.session = !root.screenState.session
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "power_settings_new"
        color: stateLayer.containsMouse ? Qt.lighter(Colours.palette.m3error, 1.2) : Colours.palette.m3error
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        scale: stateLayer.pressed ? 1.05 : stateLayer.containsMouse ? 1.2 : 1

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
