pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    implicitWidth: layout.implicitWidth + root.padding * 2
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

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

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            animate: true
            text: `${Time.hourStr}:${Time.minuteStr}`
            font: root.font.build()
            color: root.colour
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
