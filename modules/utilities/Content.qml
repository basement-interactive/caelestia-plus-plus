import "cards"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    readonly property real nonAnimHeight: idleInhibit.nonAnimHeight + record.nonAnimHeight + toggles.implicitHeight + layout.spacing * 2

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        IdleInhibit {
            id: idleInhibit

            objectName: "utilitiesKeepAwake"

            opacity: 0
            transform: Translate {
                id: idleEnter

                y: Tokens.padding.medium
            }
        }

        Record {
            id: record

            objectName: "utilitiesScreenRecorder"

            props: root.props
            screenState: root.screenState
            z: 1

            opacity: 0
            transform: Translate {
                id: recordEnter

                y: Tokens.padding.medium
            }
        }

        Toggles {
            id: toggles

            objectName: "utilitiesQuickToggles"

            screenState: root.screenState
            popouts: root.popouts

            opacity: 0
            transform: Translate {
                id: togglesEnter

                y: Tokens.padding.medium
            }
        }
    }

    // Staggered one-shot entrance for the three cards
    SequentialAnimation {
        running: true

        ParallelAnimation {
            Anim {
                target: idleInhibit
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
            Anim {
                target: idleEnter
                property: "y"
                to: 0
            }
        }
    }

    SequentialAnimation {
        running: true

        PauseAnimation {
            duration: 40
        }
        ParallelAnimation {
            Anim {
                target: record
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
            Anim {
                target: recordEnter
                property: "y"
                to: 0
            }
        }
    }

    SequentialAnimation {
        running: true

        PauseAnimation {
            duration: 80
        }
        ParallelAnimation {
            Anim {
                target: toggles
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
            Anim {
                target: togglesEnter
                property: "y"
                to: 0
            }
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
