import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const screenState = ShellState.forActive();
            screenState.launcher = !screenState.launcher;
        }
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent
        sourceComponent: {
            if (/\.(png|webp|jpe?g|tiff?)$/i.test(ShellPrefs.barLogoSource))
                return rasterIcon;
            if (!ShellPrefs.barLogoSource && SysInfo.isDefaultLogo)
                return caelestiaLogo;
            return distroIcon;
        }

        rotation: mouse.containsMouse ? 360 : 0
        scale: mouse.pressed ? 0.95 : mouse.containsMouse ? 1.15 : 1

        Behavior on rotation {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    Component {
        id: caelestiaLogo

        Logo {
            implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6 * ShellPrefs.barLogoScale)
            implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6 * ShellPrefs.barLogoScale)
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: ShellPrefs.barLogoSource || SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2 * ShellPrefs.barLogoScale)
            colour: Colours.palette.m3primary
        }
    }

    Component {
        id: rasterIcon

        // Untinted: raster logos carry their own colours
        Image {
            source: ShellPrefs.barLogoSource
            width: Math.round(Tokens.font.body.large.pointSize * 1.2 * ShellPrefs.barLogoScale)
            height: width
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }
    }
}
