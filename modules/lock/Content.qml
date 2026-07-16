import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        WeatherInfo {
            id: weatherCard

            Layout.fillWidth: true
            rootHeight: root.height

            opacity: 0
            transform: Translate {
                id: weatherSlide

                y: 12
            }
        }

        Fetch {
            id: fetchCard

            Layout.fillWidth: true
            rootHeight: root.height

            opacity: 0
            transform: Translate {
                id: fetchSlide

                y: 12
            }
        }

        Media {
            id: mediaCard

            Layout.fillWidth: true
            Layout.fillHeight: true
            lock: root.lock

            opacity: 0
            transform: Translate {
                id: mediaSlide

                y: 12
            }
        }
    }

    Center {
        lock: root.lock
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        Resources {
            id: resourcesCard

            Layout.fillWidth: true

            opacity: 0
            transform: Translate {
                id: resourcesSlide

                y: 12
            }
        }

        StyledRect {
            id: notifCard

            Layout.fillWidth: true
            Layout.fillHeight: true

            bottomRightRadius: Tokens.rounding.extraLarge
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

            opacity: 0
            transform: Translate {
                id: notifSlide

                y: 12
            }

            NotifDock {
                lock: root.lock
            }
        }
    }

    CardEntrance {
        card: weatherCard
        slide: weatherSlide
        order: 0
    }

    CardEntrance {
        card: fetchCard
        slide: fetchSlide
        order: 1
    }

    CardEntrance {
        card: mediaCard
        slide: mediaSlide
        order: 2
    }

    CardEntrance {
        card: resourcesCard
        slide: resourcesSlide
        order: 1
    }

    CardEntrance {
        card: notifCard
        slide: notifSlide
        order: 2
    }

    component CardEntrance: SequentialAnimation {
        required property Item card
        required property Translate slide
        required property int order

        running: root.opacity > 0

        PauseAnimation {
            duration: 50 * order
        }
        ParallelAnimation {
            Anim {
                type: Anim.DefaultEffects
                target: card
                property: "opacity"
                to: 1
            }
            Anim {
                target: slide
                property: "y"
                to: 0
            }
        }
    }
}
