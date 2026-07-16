pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.medium : Tokens.spacing.extraSmall

    property bool expanded

    readonly property real nonAnimWidth: {
        if (!Config.bar.tray.compact)
            return layout.implicitWidth + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitWidth + layout.implicitWidth + spacing + pad;
        return Math.max(Config.bar.tray.background ? height : 0, expandIcon.implicitWidth + pad);
    }

    clip: true
    visible: width > 0

    implicitHeight: Tokens.sizes.bar.innerWidth
    implicitWidth: nonAnimWidth

    readonly property bool hasBg: Config.bar.tray.background && items.count > 0

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, hasBg ? Colours.tPalette.m3surfaceContainer.a * 0.7 : 0)
    radius: Tokens.rounding.full
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, hasBg ? 0.4 : 0)

    // Double-bezel: inner core nested inside the hairlined shell
    StyledRect {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall / 2
        radius: root.radius
        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, root.hasBg ? Colours.tPalette.m3surfaceContainerHigh.a * 0.85 : 0)
    }

    Row {
        id: layout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        spacing: Tokens.spacing.small

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        active: Config.bar.tray.compact && items.count > 0

        sourceComponent: Item {
            implicitHeight: expandIconInner.implicitHeight
            implicitWidth: expandIconInner.implicitWidth - Tokens.padding.small

            MaterialIcon {
                id: expandIconInner

                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small
                text: "expand_less"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                rotation: root.expanded ? 90 : -90

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }
}
