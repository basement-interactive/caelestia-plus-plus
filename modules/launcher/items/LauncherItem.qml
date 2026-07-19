import QtQuick
import Caelestia.Config
import qs.components

// Shared chrome for launcher result rows: staggered entrance (only while the
// launcher is opening), press feedback and ripple. Rows declare their visuals
// as children, which land in the padded content area.
Item {
    id: root

    required property int index
    required property var list // AppList root: provides revealing + screenState

    readonly property alias pressed: pressLayer.pressed
    default property alias content: contentArea.data

    signal triggered()

    // Replays per open via the list's revealing gate. Rows created by search
    // refiltering skip it entirely: replaying a paused stagger on every
    // keystroke churned dozens of animations and produced negative-duration
    // PauseAnimation warnings (see Bible).
    function playEntrance(): void {
        opacity = 0;
        enterSlide.y = Tokens.padding.large;
        enterAnim.restart();
    }

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: Tokens.sizes.launcher.itemHeight

    scale: pressLayer.pressed ? 0.97 : 1
    transform: Translate {
        id: enterSlide
    }

    Component.onCompleted: {
        if (list.revealing)
            playEntrance();
    }

    Connections {
        target: root.list

        function onRevealingChanged(): void {
            if (root.list.revealing)
                root.playEntrance();
        }
    }

    SequentialAnimation {
        id: enterAnim

        PauseAnimation {
            duration: Math.max(0, Math.min(root.index, 8)) * 30
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
        onClicked: root.triggered()
    }

    Item {
        id: contentArea

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
    }
}
