import QtQuick
import Quickshell.Services.UPower

// Procedural animated DNA wallpaper (assets/shaders/dna.frag).
// Cost control: the shader renders into a half-resolution layer texture
// (4x fewer fragments) and only redraws when the clock timer ticks —
// 30 fps on AC, 15 fps on battery.
Item {
    id: root

    // Wrap keeps float32 phase math precise across long uptimes. This value
    // is a whole number of cycles for both helix speeds (0.35t and 0.21t),
    // so the loop point is seamless: 2*PI*50/0.35.
    readonly property real timeWrap: 897.5979010256552
    property real startMs: 0

    ShaderEffect {
        id: fx

        property real uTime: 0
        readonly property real uAspect: width / Math.max(1, height)

        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("../../assets/shaders/dna.frag.qsb")

        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.ceil(width / 2), Math.ceil(height / 2))
    }

    Timer {
        running: root.visible
        repeat: true
        triggeredOnStart: true
        interval: UPower.onBattery ? 66 : 33
        onTriggered: {
            if (root.startMs === 0)
                root.startMs = Date.now();
            fx.uTime = ((Date.now() - root.startMs) / 1000) % root.timeWrap;
        }
    }
}
