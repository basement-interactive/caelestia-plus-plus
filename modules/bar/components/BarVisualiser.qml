import QtQuick
import Caelestia.Config
import Caelestia.Internal
import Caelestia.Services
import qs.components
import qs.services

// Subtle spectrum behind the bar content, clipped to the pill shape.
// ServiceRef holds the cava FFT only while this is loaded; the tick timer
// stops once the bars settle, so silence and a hidden bar cost nothing.
StyledClippingRect {
    id: root

    // `bars.settled` latches true whenever the bars finish converging (e.g.
    // drained to zero in a silence) and assigning new values does NOT clear
    // it — the advance timer would never restart and the visualiser froze
    // flat. Track liveness from the targets we assign instead.
    property bool live: false
    property int barCount: 0

    color: "transparent"
    radius: height / 2

    ServiceRef {
        service: Audio.cava
    }

    // cava's stereo layout puts bass on both edges and near-silent treble in
    // the middle. Fold the mirrored channels to mono, then lay the spectrum
    // out as a slowly travelling triangle sweep: bass crests roll along the
    // pill like a wave instead of pinning to fixed spots, and every stretch
    // gets the same band mix over time. Assigned imperatively: a declarative
    // binding on `values` proved flaky here (see Bible).
    function retarget(): void {
        const v = Audio.cava.values;
        const n = v.length;
        if (!n)
            return;

        // Silence with the bars already drained: skip entirely. Reassigning
        // zeros on every FFT frame dirtied the (fullscreen) drawers window
        // continuously even though nothing on screen changed.
        if (!live && bars.settled) {
            let peakIn = 0;
            for (let i = 0; i < n; i++)
                peakIn = Math.max(peakIn, v[i]);
            if (peakIn < 0.004)
                return;
        }

        barCount = n;
        const half = n / 2;
        const mono = new Array(half);
        for (let b = 0; b < half; b++)
            mono[b] = (v[b] + v[n - 1 - b]) / 2;

        // 5 crests across the pill, drifting one crest-width per minute.
        // Sweep only reaches 45% into the spectrum (music barely fills the
        // rest), and a gain ramp lifts the quieter bands, so the valleys
        // between crests stay alive instead of flatlining.
        const phase = (Date.now() % 60000) / 60000;
        const sweep = new Array(n);
        for (let j = 0; j < n; j++) {
            const t = ((j / n) * 5 + phase) % 1;
            const tri = t < 0.5 ? t * 2 : 2 - t * 2;
            const band = Math.min(half - 1, Math.floor(tri * half * 0.45));
            sweep[j] = Math.min(1, mono[band] * (1.0 + 2.7 * tri));
        }

        // light box blur so neighbouring bars flow into each other
        const out = new Array(n);
        let peak = 0;
        for (let j = 0; j < n; j++) {
            const a = sweep[Math.max(0, j - 1)], c = sweep[Math.min(n - 1, j + 1)];
            out[j] = (a + 2 * sweep[j] + c) / 4;
            peak = Math.max(peak, out[j]);
        }
        bars.values = out;
        live = peak > 0.004;
    }

    Connections {
        target: Audio.cava

        function onValuesChanged(): void {
            root.retarget();
        }
    }

    Component.onCompleted: retarget()

    VisualiserBars {
        id: bars

        anchors.fill: parent
        primaryColor: Qt.alpha(Colours.palette.m3primary, 0.2)
        secondaryColor: Qt.alpha(Colours.palette.m3primaryContainer, 0.16)
        rounding: 1
        spacing: 2
        // ~1.4x: quick enough to track beats, slow enough not to strobe
        animationDuration: Math.round(Tokens.anim.durations.normal * 1.4)

        // The compiled renderer ALWAYS lays fixed 6px bars at 2px gaps from
        // the left (both `spacing` and item width are ignored) and draws at
        // most 96 bars — keep visualiserBars at 96 and `spacing` at the real
        // value 2. Stretch the 766px natural span across the pill here.
        // root.barCount is set imperatively in retarget(): bindings that read
        // bars.values directly can capture a stale array and never re-evaluate
        transform: Scale {
            xScale: bars.width / Math.max(1, root.barCount * 8 - 2)
        }
    }

    // Fixed 30 fps tick instead of FrameAnimation: half the redraws of the
    // drawers window (and its shadow layer) for a bar that reads the same
    Timer {
        // barCount === 0 means retarget() never received FFT data, so there
        // are no targets to converge on — without this guard `bars.settled`
        // stays false forever and the tick redraws the bar at 30 fps for
        // nothing (measured: continuous drawers-window renders in silence)
        running: root.visible && root.barCount > 0 && (root.live || !bars.settled)
        repeat: true
        interval: 33
        onTriggered: bars.advance(0.033)
    }
}
