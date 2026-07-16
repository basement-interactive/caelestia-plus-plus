pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3primary
    property bool fullscreen: false
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    implicitWidth: layout.implicitWidth + root.padding * 2
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a * 0.7 : 0)
    radius: Tokens.rounding.full
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, Config.bar.clock.background ? 0.4 : 0)
    scale: hover.hovered ? 1.05 : 1

    HoverHandler {
        id: hover
    }

    Behavior on scale {
        Anim {
            type: Anim.FastSpatial
        }
    }

    // Double-bezel: inner core nested inside the hairlined shell
    StyledRect {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall / 2
        radius: root.radius
        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainerHigh.a * 0.85 : 0)
    }

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active

            sourceComponent: RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    animate: true
                    text: Time.format("ddd d")
                    font: root.font.scale(0.9).build()
                    color: root.colour
                }

                StyledRect {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillHeight: true
                    Layout.topMargin: Tokens.padding.extraSmall
                    Layout.bottomMargin: Tokens.padding.extraSmall
                    implicitWidth: 1
                    color: Colours.palette.m3outlineVariant
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                animate: true
                text: Time.hourStr
                font: root.font.build()
                color: root.colour
            }

            StyledText {
                text: ":"
                font: root.font.build()
                color: root.colour

                SequentialAnimation on opacity {
                    running: root.visible && !root.fullscreen
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    Anim {
                        to: 0.45
                        duration: Tokens.anim.durations.extraLarge * 3
                        easing: Tokens.anim.standardAccel
                    }
                    Anim {
                        to: 1
                        duration: Tokens.anim.durations.extraLarge * 3
                        easing: Tokens.anim.standardDecel
                    }
                }
            }

            StyledText {
                animate: true
                text: Time.minuteStr
                font: root.font.build()
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: GlobalConfig.services.useTwelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }
    }
}
