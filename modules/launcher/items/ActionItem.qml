import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property var list
    required property int index

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    opacity: 0
    scale: pressLayer.pressed ? 0.97 : 1
    transform: Translate {
        id: enterSlide

        y: Tokens.padding.large
    }

    SequentialAnimation {
        running: true

        PauseAnimation {
            duration: Math.min(root.index, 10) * 30
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
            Anim {
                target: enterSlide
                property: "y"
                to: 0
                type: Anim.DefaultSpatial
            }
        }
    }

    Behavior on scale {
        Anim {
            type: pressLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
        }
    }

    StateLayer {
        id: pressLayer

        radius: Tokens.rounding.large
        onClicked: root.modelData?.onClicked(root.list)
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData?.icon ?? ""
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width
            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
            }

            StyledText {
                id: desc

                text: root.modelData?.desc ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - Tokens.rounding.extraLargeIncreased

                anchors.top: name.bottom
            }
        }
    }
}
