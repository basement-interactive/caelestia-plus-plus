pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop easter egg: `qs -c caelestia ipc call israelEgg pop` plays
// israel.mp3 at 30% volume under a full-screen cinematic - letterbox
// bars, a dimmed backdrop, rotating light rays, a glowing Star of David
// between two flag stripes, and drifting sparks. Everything fades out
// when the track ends. Triggered by typing i-s-r-a-e-l on an empty
// desktop (same evdev watcher as the other egg). Clicks pass through.
Scope {
    id: root

    // 0 idle, 1 playing, 2 fading out
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
        running: root.phase === 2
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
                    volume: 0.3
                }

                Component.onCompleted: play()
                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.EndOfMedia)
                        root.phase = 2;
                }
                // A broken file would otherwise leave the overlay up forever
                onErrorOccurred: root.phase = 2
            }

            // Backstop for the same reason, in case neither signal fires
            Timer {
                interval: 30000
                running: root.phase === 1
                onTriggered: root.phase = 2
            }

            Item {
                id: scene

                readonly property real starRadius: Math.min(width, height) * 0.21
                readonly property real centerY: height * 0.46

                // 0 -> 1 over the intro; drives the fade-in and bar slide
                property real reveal: 0

                anchors.fill: parent
                opacity: root.phase === 2 ? 0 : 1

                NumberAnimation on reveal {
                    from: 0
                    to: 1
                    duration: 1400
                    easing.type: Easing.OutCubic
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1200
                        easing.type: Easing.InQuad
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#050d26"
                    opacity: scene.reveal * 0.55
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

                // Slow-turning rays behind the star
                Item {
                    id: rays

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: scene.centerY
                    opacity: scene.reveal * 0.14

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
                            height: scene.starRadius * 3.2
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

                // Flag stripes sweeping open above and below the star
                component FlagStripe: Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * scene.reveal
                    height: scene.starRadius * 0.18
                    color: "#0038b8"
                    opacity: 0.9
                }

                FlagStripe {
                    y: scene.centerY - scene.starRadius * 1.65 - height
                }

                FlagStripe {
                    y: scene.centerY + scene.starRadius * 1.65
                }

                // The star itself: two overlapping triangles, a wide soft
                // blue stroke underneath a crisp white one. Breathes with
                // the pulse; pulse feeds bindings directly - running it
                // through a Behavior would freeze it (see Bible:
                // qml-behavior-retarget-freeze)
                Item {
                    id: star

                    property real pulse: 0

                    readonly property real boxRadius: width / 2

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: scene.centerY - height / 2
                    width: scene.starRadius * 2.4
                    height: width
                    scale: 0.96 + pulse * 0.05

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

                    // Entrance: unfold from nothing once the window loads
                    NumberAnimation on opacity {
                        from: 0
                        to: 1
                        duration: 1600
                        easing.type: Easing.OutCubic
                    }

                    function trianglePoints(startDeg) {
                        const r = boxRadius / 1.2;
                        const pts = [];
                        for (let i = 0; i <= 3; i++) {
                            const a = (startDeg + i * 120) * Math.PI / 180;
                            pts.push(Qt.point(boxRadius + r * Math.cos(a), boxRadius + r * Math.sin(a)));
                        }
                        return pts;
                    }

                    component StarShape: Shape {
                        id: outline

                        property real lineWidth
                        property color lineColor

                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: outline.lineWidth
                            strokeColor: outline.lineColor
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline {
                                path: star.trianglePoints(-90)
                            }
                        }

                        ShapePath {
                            strokeWidth: outline.lineWidth
                            strokeColor: outline.lineColor
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline {
                                path: star.trianglePoints(90)
                            }
                        }
                    }

                    StarShape {
                        lineWidth: 16
                        lineColor: "#3d6bff"
                        opacity: 0.25 + star.pulse * 0.2
                    }

                    StarShape {
                        lineWidth: 5
                        lineColor: "#f4f7ff"
                    }
                }

                // Sparks drifting up the screen on one shared clock
                Item {
                    id: sparks

                    property real clock: 0

                    anchors.fill: parent
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
            }
        }
    }
}
