import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Left pillar of the dashboard tab: clock on top, current weather below.
// Replaces the old separate DateTime strip and SmallWeather card, whose
// mismatched sizes left dead space and ragged column edges in the grid.
Item {
    id: root

    anchors.fill: parent

    Component.onCompleted: Weather.reload()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: 0

        Item {
            Layout.fillHeight: true
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: -(font.pointSize * 0.4)
            text: Time.hourStr
            color: Colours.palette.m3secondary
            font: Tokens.font.clock.size(34).weight(Font.DemiBold).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "•••"
            color: Colours.palette.m3primary
            font: Tokens.font.clock.size(34 * 0.9).build()

            // Slow breathing pulse; gated on visibility so it never keeps
            // the window rendering while the dashboard is closed
            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite

                Anim {
                    to: 0.35
                    duration: 1400
                    type: Anim.SlowEffects
                }
                Anim {
                    to: 1
                    duration: 1400
                    type: Anim.SlowEffects
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -(font.pointSize * 0.4)
            text: Time.minuteStr
            color: Colours.palette.m3secondary
            font: Tokens.font.clock.size(34).weight(Font.DemiBold).build()
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true

            active: GlobalConfig.services.useTwelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr
                color: Colours.palette.m3primary
                font: Tokens.font.clock.size(20).weight(Font.DemiBold).build()
            }
        }

        Item {
            Layout.fillHeight: true
        }

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            animate: true
            text: Weather.icon
            color: Colours.palette.m3secondary
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.5).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            animate: true
            text: Weather.temp
            color: Colours.palette.m3primary
            font: Tokens.font.headline.builders.medium.width(110).weight(Font.DemiBold).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.extraSmall
            Layout.maximumWidth: root.width - Tokens.padding.extraLarge * 2
            animate: true
            text: Weather.description
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
