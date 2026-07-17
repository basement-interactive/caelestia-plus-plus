pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop easter egg: `qs -c caelestia ipc call israelEgg pop` plays
// israel.mp3 at 80% volume under a fullscreen three-act cinematic -
// a glowing Star of David, then the flag sweeping in and waving, then
// the statesman portrait rising under a rain of floating eyes - with
// a white flash between acts. Everything fades out when
// the track ends. Triggered by typing i-s-r-a-e-l on an empty desktop
// (same evdev watcher as the other egg). Clicks pass through.
Scope {
    id: root

    // 0 idle, 1 star act, 2 flag act, 3 portrait act, 4 fading out
    property int phase: 0

    IpcHandler {
        target: "israelEgg"

        function pop(): void {
            if (root.phase === 0)
                root.phase = 1;
        }
    }

    // Keeps the window alive just past the 1200ms outro fade
    Timer {
        running: root.phase === 4
        interval: 1300
        onTriggered: root.phase = 0
    }

    LazyLoader {
        active: root.phase !== 0

        PanelWindow {
            id: window

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "caelestia-israelegg"

            // Empty input region: purely decorative, clicks pass through
            mask: Region {}

            MediaPlayer {
                id: track

                source: Qt.resolvedUrl("../../assets/israel.mp3")
                audioOutput: AudioOutput {
                    volume: 0.8
                }

                Component.onCompleted: play()
                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.EndOfMedia)
                        root.phase = 4;
                }
                // A broken file would otherwise leave the overlay up forever
                onErrorOccurred: root.phase = 4
            }

            // Backstop for the same reason, in case neither signal fires
            Timer {
                interval: 30000
                running: root.phase >= 1 && root.phase <= 3
                onTriggered: root.phase = 4
            }

            // Act changes; the ~18s track covers act 3 until EndOfMedia
            SequentialAnimation {
                running: true

                PauseAnimation {
                    duration: 4200
                }
                ScriptAction {
                    script: {
                        root.phase = 2;
                        actFlash.restart();
                    }
                }
                PauseAnimation {
                    duration: 5800
                }
                ScriptAction {
                    script: {
                        root.phase = 3;
                        actFlash.restart();
                    }
                }
            }

            Item {
                id: scene

                readonly property real centerY: height * 0.46

                // 0 -> 1 over the intro; drives the fade-in and bar slide
                property real reveal: 0
                // Shared breathing clock for every glow and throb
                property real pulse: 0
                // White blink covering each act transition
                property real flash: 0

                anchors.fill: parent
                opacity: root.phase === 4 ? 0 : 1

                NumberAnimation on reveal {
                    from: 0
                    to: 1
                    duration: 1400
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation on pulse {
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 1
                        duration: 1600
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0
                        duration: 1600
                        easing.type: Easing.InOutSine
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1200
                        easing.type: Easing.InQuad
                    }
                }

                SequentialAnimation {
                    id: actFlash

                    NumberAnimation {
                        target: scene
                        property: "flash"
                        to: 0.75
                        duration: 110
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: scene
                        property: "flash"
                        to: 0
                        duration: 480
                        easing.type: Easing.InQuad
                    }
                }

                // Two overlapping stroked triangles; used by the hero star
                // and the flag's smaller one
                component TrianglePair: Shape {
                    id: pair

                    property real lineWidth
                    property color lineColor
                    property var upPoints
                    property var downPoints

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: pair.lineWidth
                        strokeColor: pair.lineColor
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: pair.upPoints
                        }
                    }

                    ShapePath {
                        strokeWidth: pair.lineWidth
                        strokeColor: pair.lineColor
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: pair.downPoints
                        }
                    }
                }

                component MagenDavid: Item {
                    id: magen

                    property color lineColor: "#f4f7ff"
                    property color glowColor: "#3d6bff"
                    readonly property real lineWidth: width * 0.028

                    height: width

                    function trianglePoints(startDeg) {
                        const r = width / 2 / 1.2;
                        const pts = [];
                        for (let i = 0; i <= 3; i++) {
                            const a = (startDeg + i * 120) * Math.PI / 180;
                            pts.push(Qt.point(width / 2 + r * Math.cos(a), width / 2 + r * Math.sin(a)));
                        }
                        return pts;
                    }

                    readonly property var upPoints: trianglePoints(-90)
                    readonly property var downPoints: trianglePoints(90)

                    TrianglePair {
                        lineWidth: magen.lineWidth * 3
                        lineColor: magen.glowColor
                        upPoints: magen.upPoints
                        downPoints: magen.downPoints
                        opacity: 0.25 + scene.pulse * 0.2
                    }

                    TrianglePair {
                        lineWidth: magen.lineWidth
                        lineColor: magen.lineColor
                        upPoints: magen.upPoints
                        downPoints: magen.downPoints
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#050d26"
                    opacity: scene.reveal * 0.55
                }

                // Slow-turning rays; follow the current act's centerpiece
                Item {
                    id: rays

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.phase >= 3 ? parent.height * 0.42 : scene.centerY
                    opacity: scene.reveal * (root.phase >= 3 ? 0.2 : 0.14)

                    Behavior on y {
                        NumberAnimation {
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }

                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 40000
                        loops: Animation.Infinite
                    }

                    Repeater {
                        model: 8

                        Rectangle {
                            required property int index

                            x: -width / 2
                            y: -height
                            width: 3
                            height: Math.min(window.width, window.height) * 0.68
                            rotation: index * 45
                            transformOrigin: Item.Bottom
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }
                                GradientStop {
                                    position: 1
                                    color: "#dce6ff"
                                }
                            }
                        }
                    }
                }

                // Act 2 centerpiece; parks small at the top for act 3
                Item {
                    id: flag

                    property real wave: 0
                    readonly property real targetCx: window.width / 2
                    readonly property real targetCy: root.phase >= 3 ? window.height * 0.17 : scene.centerY

                    width: window.width * 0.46
                    height: width * 8 / 11
                    x: (root.phase >= 2 ? targetCx : -width) - width / 2
                    y: targetCy - height / 2
                    scale: root.phase >= 3 ? 0.5 : 1
                    rotation: wave
                    opacity: root.phase >= 2 ? 1 : 0

                    Behavior on x {
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }

                    SequentialAnimation on wave {
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 2.5
                            duration: 1400
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: -2.5
                            duration: 1400
                            easing.type: Easing.InOutSine
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "#fdfdfd"
                        border.color: "#c9d4e8"
                        border.width: 1
                    }

                    component FlagStripe: Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: parent.width * 0.02
                        anchors.rightMargin: parent.width * 0.02
                        height: parent.height * 0.11
                        color: "#0038b8"
                    }

                    FlagStripe {
                        y: flag.height * 0.14
                    }

                    FlagStripe {
                        y: flag.height * 0.75
                    }

                    MagenDavid {
                        anchors.centerIn: parent
                        width: flag.height * 0.5
                        lineColor: "#0038b8"
                        glowColor: "#0038b8"
                    }
                }

                // Act 1 centerpiece; the act-2 flash covers its hard cut
                MagenDavid {
                    id: heroStar

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: scene.centerY - height / 2
                    width: Math.min(window.width, window.height) * 0.5
                    scale: 0.96 + scene.pulse * 0.05
                    opacity: scene.reveal * (root.phase === 1 ? 1 : 0)
                }

                // Act 3 centerpiece: rises from the bottom edge, sways
                Image {
                    id: bibi

                    // 0 sunk below the edge, 1 fully risen
                    property real rise: root.phase >= 3 ? 1 : 0
                    property real sway: 0

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: window.height - height * rise
                    height: window.height * 0.52
                    width: height * 0.8
                    sourceSize: Qt.size(width, height)
                    source: Qt.resolvedUrl("../../assets/israel-bibi.svg")
                    transformOrigin: Item.Bottom
                    rotation: sway
                    scale: 1 + scene.pulse * 0.03

                    Behavior on rise {
                        NumberAnimation {
                            duration: 900
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                        }
                    }

                    SequentialAnimation on sway {
                        running: root.phase >= 3
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 2.5
                            duration: 1100
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: -2.5
                            duration: 1100
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                // Act 3 weather: floating eyes drifting down on one clock
                Item {
                    id: eyeRain

                    property real clock: 0

                    anchors.fill: parent
                    opacity: root.phase >= 3 ? 1 : 0

                    NumberAnimation on clock {
                        from: 0
                        to: 1
                        duration: 3400
                        loops: Animation.Infinite
                    }

                    Repeater {
                        model: 22

                        Item {
                            id: eye

                            required property int index

                            // Per-eye lane, fall offset and size, rolled once
                            readonly property real lane: Math.random()
                            readonly property real drop: Math.random()
                            readonly property real t: (eyeRain.clock + drop) % 1

                            x: lane * eyeRain.width + Math.sin(t * 12.6 + drop * 6.3) * 30
                            y: -height + (eyeRain.height + 2 * height) * t
                            width: 30 + (index % 3) * 8
                            height: width * 0.6
                            rotation: Math.sin(t * 6.3 + drop * 6.3) * 16

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: "#fdfdfd"
                                border.color: "#c9d4e8"
                                border.width: 1
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: eye.height * 0.62
                                height: width
                                radius: width / 2
                                color: "#2e6bd6"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.45
                                    height: width
                                    radius: width / 2
                                    color: "#101318"
                                }
                            }
                        }
                    }
                }

                // Sparks drifting up behind everything, all acts
                Item {
                    id: sparks

                    property real clock: 0

                    anchors.fill: parent
                    z: -1
                    opacity: scene.reveal

                    NumberAnimation on clock {
                        from: 0
                        to: 1
                        duration: 7000
                        loops: Animation.Infinite
                    }

                    Repeater {
                        model: 28

                        Rectangle {
                            required property int index

                            // Per-spark lane and offset, rolled once at creation
                            readonly property real lane: Math.random()
                            readonly property real drift: Math.random()
                            readonly property real t: (sparks.clock + drift) % 1

                            x: lane * sparks.width
                            y: sparks.height * (1 - t)
                            width: 3 + (index % 3) * 2
                            height: width
                            radius: width / 2
                            color: index % 4 === 0 ? "#7d9bff" : "#f4f7ff"
                            opacity: Math.sin(t * Math.PI) * 0.7
                        }
                    }
                }

                // Letterbox bars sliding in from the screen edges
                component LetterboxBar: Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: parent.height * 0.075
                    color: "#000000"
                }

                LetterboxBar {
                    y: -height + height * scene.reveal
                }

                LetterboxBar {
                    y: parent.height - height * scene.reveal
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#ffffff"
                    opacity: scene.flash
                }
            }
        }
    }
}
