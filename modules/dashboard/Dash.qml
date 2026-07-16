import "dash"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services

GridLayout {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    rowSpacing: Tokens.spacing.medium
    columnSpacing: Tokens.spacing.medium

    Rect {
        stagger: 1

        Layout.column: 2
        Layout.columnSpan: 3
        Layout.preferredWidth: Tokens.sizes.dashboard.userWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge

        User {
            id: user

            screenState: root.screenState
            facePicker: root.facePicker
        }
    }

    Rect {
        stagger: 0

        Layout.row: 0
        Layout.columnSpan: 2
        Layout.preferredWidth: Tokens.sizes.dashboard.weatherWidth
        Layout.preferredHeight: weather.implicitHeight

        radius: Tokens.rounding.extraLarge * 1.5

        SmallWeather {
            id: weather
        }
    }

    Rect {
        stagger: 3

        Layout.row: 1
        Layout.preferredWidth: dateTime.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.large

        DateTime {
            id: dateTime
        }
    }

    Rect {
        stagger: 4

        Layout.row: 1
        Layout.column: 1
        Layout.columnSpan: 3
        Layout.fillWidth: true
        Layout.preferredHeight: calendar.implicitHeight

        radius: Tokens.rounding.extraLarge

        Calendar {
            id: calendar

            screenState: root.screenState
        }
    }

    Rect {
        stagger: 5

        Layout.row: 1
        Layout.column: 4
        Layout.preferredWidth: resources.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.large

        Resources {
            id: resources
        }
    }

    Rect {
        stagger: 2

        Layout.row: 0
        Layout.column: 5
        Layout.rowSpan: 2
        Layout.preferredWidth: media.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge * 2

        Media {
            id: media
        }
    }

    component Rect: StyledRect {
        id: card

        property int stagger: 0
        property real revealOffset: Tokens.padding.large

        color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.7)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        opacity: 0
        transform: Translate {
            y: card.revealOffset
        }

        Behavior on border.color {
            CAnim {}
        }

        StyledRect {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall
            radius: Math.max(0, card.radius - anchors.margins)
            color: Colours.tPalette.m3surfaceContainer
        }

        SequentialAnimation {
            running: true

            PauseAnimation {
                duration: card.stagger * 40
            }
            ParallelAnimation {
                Anim {
                    target: card
                    property: "opacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
                Anim {
                    target: card
                    property: "revealOffset"
                    to: 0
                    type: Anim.DefaultSpatial
                }
            }
        }
    }
}
