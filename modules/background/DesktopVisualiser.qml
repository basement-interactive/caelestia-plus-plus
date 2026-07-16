pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// NCS-style circular audio visualiser for the desktop: a pulsing core ring
// with mirrored spectrum bars radiating outward. Bass sits at the bottom,
// treble at the top, left/right symmetric.
//
// Deliberately cheap to run:
// - Bars are GPU ShapePath lines; they only re-evaluate when the in-process
//   cava provider pushes new values. On silence the values rest at zero, so
//   nothing repaints and the widget costs nothing.
// - ServiceRef refcounts Audio.cava: the FFT itself only runs while this
//   (or another consumer) is alive.
// - No timers, no Canvas, no per-frame animation.
Item {
    id: root

    required property ShellScreen screen

    // Only exists while the desktop is actually visible: with tiled windows
    // on the workspace the Loader unloads, releasing the cava ServiceRef so
    // even the FFT stops. True zero cost while working.
    readonly property bool shouldBeActive: Hypr.monitorFor(screen)?.activeWorkspace?.toplevels?.values.every(t => t.lastIpcObject?.floating) ?? true

    readonly property int barCount: GlobalConfig.services.visualiserBars
    readonly property real coreRadius: screen.height * 0.09
    readonly property real maxMagnitude: screen.height * 0.13
    readonly property real barGap: Tokens.spacing.small

    // Average of the low end (post-curve), drives the core pulse. Quantized
    // so pulse-driven bindings only fire on visible change, not every frame.
    readonly property real bass: {
        const vals = Audio.cava.values;
        const n = Math.min(6, vals.length);
        let sum = 0;
        for (let i = 0; i < n; i++)
            sum += curve(vals[i]);
        return n > 0 ? Math.round(sum / n * 24) / 24 : 0;
    }

    // Noise floor + gamma: ignores quiet sounds, keeps loud ones expressive.
    function curve(v: real): real {
        const t = Math.max(0, Math.min(1, v) - 0.07) / 0.93;
        return Math.pow(t, 1.6);
    }

    implicitWidth: (coreRadius + barGap + maxMagnitude) * 2
    implicitHeight: implicitWidth

    opacity: shouldBeActive ? 1 : 0
    scale: shouldBeActive ? 1 : 0.85

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on scale {
        Anim {}
    }

    // Holds the cava reference only while visible; unloading stops the FFT.
    Loader {
        active: root.opacity > 0

        sourceComponent: Item {
            ServiceRef {
                service: Audio.cava
            }
        }
    }

    // Soft red halo behind the core, breathing with the bass.
    RectangularShadow {
        anchors.centerIn: parent
        width: core.width
        height: core.height
        radius: width / 2
        color: Qt.alpha(Colours.palette.m3primary, 0.25 + root.bass * 0.45)
        blur: Tokens.padding.large * 2.5
        spread: 1
        offset: Qt.vector2d(0, 0)
        scale: core.scale
    }

    // Core ring.
    StyledRect {
        id: core

        anchors.centerIn: parent
        implicitWidth: root.coreRadius * 2
        implicitHeight: root.coreRadius * 2
        radius: root.coreRadius
        color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.45)
        border.width: Math.max(2, Tokens.padding.extraSmall / 2)
        border.color: Colours.palette.m3primary
        scale: 1 + root.bass * 0.07
    }

    // Bars as plain Rectangles under a static per-bar rotation: the transform
    // matrix is computed once, so an audio frame only updates 48 quad heights.
    // Far cheaper than Shape paths, which re-triangulate on every change.
    Item {
        anchors.fill: parent

        Repeater {
            model: root.barCount

            Item {
                id: bar

                required property int index

                // Mirror the spectrum across the vertical axis; bass at the bottom.
                readonly property int specIdx: {
                    const half = root.barCount / 2;
                    return index < half ? index : root.barCount - 1 - index;
                }
                readonly property real value: root.curve(Audio.cava.values[specIdx] ?? 0)
                readonly property real barWidth: (2 * Math.PI * root.coreRadius / root.barCount) * 0.5

                width: barWidth
                height: root.maxMagnitude
                x: root.width / 2 - barWidth / 2
                y: root.height / 2 - root.coreRadius - root.barGap - height

                transform: Rotation {
                    origin.x: bar.barWidth / 2
                    origin.y: bar.height + root.coreRadius + root.barGap
                    angle: 180 + (bar.index + 0.5) * 360 / root.barCount
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter

                    width: bar.barWidth
                    height: Math.max(width, bar.value * root.maxMagnitude)
                    radius: width / 2
                    color: Colours.palette.m3primary
                    antialiasing: true
                }
            }
        }
    }
}
