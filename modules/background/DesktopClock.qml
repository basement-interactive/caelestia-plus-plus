pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Item wallpaper
    // The animated wallpaper item when one is active (null on static images);
    // the glass grab re-renders in lockstep with its frames
    property Item animationTicker
    required property real absX
    required property real absY

    property real clockScale: Config.background.desktopClock.scale
    readonly property bool bgEnabled: Config.background.desktopClock.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopClock.background.blur && !GameMode.enabled
    readonly property bool invertColors: Config.background.desktopClock.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary

    implicitWidth: layout.implicitWidth + (Tokens.padding.large * 4 * root.clockScale)
    implicitHeight: layout.implicitHeight + (Tokens.padding.extraLargeIncreased * root.clockScale)

    Item {
        id: clockContainer

        anchors.fill: parent

        layer.enabled: Config.background.desktopClock.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopClock.shadow.opacity
            shadowBlur: Config.background.desktopClock.shadow.blur
        }

        Loader {
            asynchronous: true
            anchors.fill: parent
            active: root.blurEnabled

            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    id: glassSource

                    sourceItem: root.wallpaper
                    sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
                    // The grab feeds a heavy blur, so half resolution is
                    // indistinguishable and quarters the per-frame cost
                    textureSize: Qt.size(Math.ceil(root.width / 2), Math.ceil(root.height / 2))

                    // A live grab re-rendered this window on every wallpaper
                    // frame ON TOP of the wallpaper's own render (measured
                    // ~60 fps on the background window). Grabbing on the
                    // wallpaper's own frame signal keeps them in lockstep —
                    // one window render per wallpaper frame, none on a
                    // static image.
                    live: false
                    Component.onCompleted: scheduleUpdate()

                    Connections {
                        target: root.animationTicker
                        ignoreUnknownSignals: true

                        function onFrameAdvanced(): void {
                            glassSource.scheduleUpdate();
                        }
                    }

                    // Covers the crossfade when a static wallpaper is set or changed
                    Timer {
                        id: wallpaperSwitchBurst

                        interval: 2000
                        onRunningChanged: glassBurstTick.running = running
                    }

                    Timer {
                        id: glassBurstTick

                        repeat: true
                        interval: 33
                        onTriggered: glassSource.scheduleUpdate()
                    }

                    Connections {
                        target: Wallpapers

                        function onCurrentChanged(): void {
                            wallpaperSwitchBurst.restart();
                        }
                    }
                }
                maskSource: backgroundPlate
                maskEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        StyledRect {
            id: backgroundPlate

            visible: root.bgEnabled
            anchors.fill: parent
            radius: Tokens.rounding.extraLarge * root.clockScale
            opacity: Config.background.desktopClock.background.opacity
            color: Colours.palette.m3surface

            layer.enabled: root.blurEnabled
        }

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Tokens.spacing.large * root.clockScale

            RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    text: Time.hourStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).weight(Font.Bold).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: ":"
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).build()
                    color: root.safeTertiary
                    opacity: 0.8
                    Layout.topMargin: -Tokens.padding.large * 1.5 * root.clockScale
                }

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).weight(Font.Bold).build()
                    color: root.safeSecondary
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.large * 1.4 * root.clockScale

                    active: GlobalConfig.services.useTwelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.clockScale).build()
                        color: root.safeSecondary
                    }
                }
            }

            StyledRect {
                Layout.fillHeight: true
                Layout.preferredWidth: 4 * root.clockScale
                Layout.topMargin: Tokens.spacing.large * root.clockScale
                Layout.bottomMargin: Tokens.spacing.large * root.clockScale
                radius: Tokens.rounding.full
                color: root.safePrimary
                opacity: 0.8
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: Time.format("MMMM").toUpperCase()
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.clockScale).letterSpacing(4).weight(Font.Bold).build()
                    color: root.safeSecondary
                }

                StyledText {
                    text: Time.format("dd")
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * root.clockScale).letterSpacing(2).weight(Font.Medium).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: Time.format("dddd")
                    font: Tokens.font.clock.size(Tokens.font.body.large.pointSize * root.clockScale).letterSpacing(2).build()
                    color: root.safeSecondary
                }
            }
        }
    }

    Behavior on clockScale {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
