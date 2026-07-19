pragma ComponentBehavior: Bound

import "dash"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services

// Bento grid: two full-height pillars (clock+weather left, media right)
// framing a center column of user card over calendar and resource gauges.
// Every card stretches to the panel's locked size — no ragged edges.
GridLayout {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    // Cards replay their entrance every time the dashboard opens: this pane
    // is preloaded at startup, so a run-once animation would play unseen
    readonly property bool revealed: screenState.dashboard

    rowSpacing: Tokens.spacing.medium
    columnSpacing: Tokens.spacing.medium

    Rect {
        stagger: 0

        Layout.row: 0
        Layout.column: 0
        Layout.rowSpan: 2
        Layout.preferredWidth: Tokens.sizes.dashboard.mediaWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge * 2

        NowCard {}
    }

    Rect {
        stagger: 1

        Layout.row: 0
        Layout.column: 1
        Layout.columnSpan: 2
        Layout.fillWidth: true
        // Fixed header band; the avatar and badges inside anchor-fill it
        Layout.preferredHeight: 116

        User {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }

    Rect {
        stagger: 2

        Layout.row: 1
        Layout.column: 1
        Layout.fillWidth: true
        Layout.fillHeight: true

        Calendar {
            screenState: root.screenState
        }
    }

    Rect {
        stagger: 3

        Layout.row: 1
        Layout.column: 2
        Layout.preferredWidth: resources.implicitWidth
        Layout.fillHeight: true

        Resources {
            id: resources
        }
    }

    Rect {
        stagger: 4

        Layout.row: 0
        Layout.column: 3
        Layout.rowSpan: 2
        Layout.preferredWidth: media.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge * 2

        Media {
            id: media
        }
    }

    component Rect: Card {
        id: card

        property int stagger: 0
        property real revealOffset: Tokens.padding.large
        readonly property bool revealed: root.revealed

        opacity: 0
        scale: 0.96
        transform: Translate {
            y: card.revealOffset
        }

        onRevealedChanged: {
            if (revealed) {
                reveal.restart();
            } else {
                reveal.stop();
                opacity = 0;
                scale = 0.96;
                revealOffset = Tokens.padding.large;
            }
        }
        Component.onCompleted: {
            if (revealed)
                reveal.restart();
        }

        SequentialAnimation {
            id: reveal

            PauseAnimation {
                // Base delay lets the drawer slide-in land first, so the
                // cascade is actually seen instead of playing off-screen
                duration: 150 + card.stagger * 60
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
                    property: "scale"
                    to: 1
                    type: Anim.DefaultSpatial
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
