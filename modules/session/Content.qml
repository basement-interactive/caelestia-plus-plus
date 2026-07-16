pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Column {
    id: root

    required property ScreenState screenState

    padding: Tokens.padding.large
    rightPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
    spacing: Tokens.spacing.large

    SessionButton {
        id: logout

        entranceIndex: 0
        icon: Config.session.icons.logout
        command: Config.session.commands.logout
        KeyNavigation.down: shutdown

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    logout.forceActiveFocus();
            }

            target: root.screenState
        }
    }

    SessionButton {
        id: shutdown

        entranceIndex: 1
        icon: Config.session.icons.shutdown
        command: Config.session.commands.shutdown
        KeyNavigation.up: logout
        KeyNavigation.down: hibernate
    }

    AnimatedImage {
        width: Tokens.sizes.session.button
        height: Tokens.sizes.session.button
        sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)

        playing: visible
        asynchronous: true
        speed: Config.general.sessionGifSpeed
        source: Paths.absolutePath(Config.paths.sessionGif)
        fillMode: AnimatedImage.PreserveAspectFit
    }

    SessionButton {
        id: hibernate

        entranceIndex: 2
        icon: Config.session.icons.hibernate
        command: Config.session.commands.hibernate
        KeyNavigation.up: shutdown
        KeyNavigation.down: reboot
    }

    SessionButton {
        id: reboot

        entranceIndex: 3
        icon: Config.session.icons.reboot
        command: Config.session.commands.reboot
        KeyNavigation.up: hibernate
    }

    component SessionButton: IconButton {
        id: button

        required property list<string> command
        property int entranceIndex

        function exec(): void {
            if (!SessionManager.exec(command))
                Quickshell.execDetached(command);
        }

        implicitWidth: Tokens.sizes.session.button
        implicitHeight: Tokens.sizes.session.button

        inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        font: Tokens.font.icon.builders.large.scale(1.3).build()

        border.width: 1
        border.color: activeFocus ? Qt.alpha(Colours.palette.m3primary, 0.4) : Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

        scale: pressed ? 0.97 : 1
        opacity: 0
        transform: Translate {
            id: slide

            x: Tokens.padding.large
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on border.color {
            CAnim {}
        }

        SequentialAnimation {
            running: true

            PauseAnimation {
                duration: button.entranceIndex * 40
            }
            ParallelAnimation {
                Anim {
                    type: Anim.DefaultEffects
                    target: button
                    property: "opacity"
                    to: 1
                }
                Anim {
                    target: slide
                    property: "x"
                    to: 0
                }
            }
        }
        onClicked: exec()

        Keys.onEnterPressed: exec()
        Keys.onReturnPressed: exec()
        Keys.onEscapePressed: root.screenState.session = false
        Keys.onPressed: event => {
            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && KeyNavigation.down) {
                    KeyNavigation.down.focus = true;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab && KeyNavigation.down) {
                KeyNavigation.down.focus = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            }
        }
    }
}
