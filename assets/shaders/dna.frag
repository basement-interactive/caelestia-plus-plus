#version 440

// Animated DNA double helix, red on near-black. Runs half-res behind a
// linear upscale (layer.textureSize in DnaBackground.qml) — keep it ALU-only:
// no texture taps, no loops, two helix evaluations + one dust layer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uAspect;
};

const float PI = 3.14159265;

// Scheme accents: m3primaryContainer, m3primary, hot highlight
const vec3 C_DEEP = vec3(0.576, 0.000, 0.039); // 93000a
const vec3 C_MAIN = vec3(1.000, 0.329, 0.286); // ff5449
const vec3 C_HOT  = vec3(1.000, 0.769, 0.722); // ffc4b8

float hash(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// One double helix along +x of p, additive colour.
// amp: strand radius, thick: core half-width, glowK: halo falloff
vec3 helix(vec2 p, float t, float amp, float thick, float glowK, float bright) {
    float ph = p.x * 6.0 + t;
    float s = sin(ph), c = cos(ph);
    float y1 = s * amp;           // strand 1; strand 2 is phase + PI => -y1
    float dp1 = c * 0.5 + 0.5;    // depth: 0 = back, 1 = front
    float dp2 = 1.0 - dp1;

    float d1 = abs(p.y - y1);
    float d2 = abs(p.y + y1);

    // front strand renders thicker and brighter, back one thin and dim
    float w1 = thick * mix(0.55, 1.15, dp1);
    float w2 = thick * mix(0.55, 1.15, dp2);
    float core1 = smoothstep(w1, w1 * 0.35, d1);
    float core2 = smoothstep(w2, w2 * 0.35, d2);
    float glow1 = exp(-d1 * d1 * glowK);
    float glow2 = exp(-d2 * d2 * glowK);

    // fake occlusion: whichever strand is in front eats the other at crossings
    float front1 = step(dp2, dp1);
    core2 *= 1.0 - core1 * front1 * 0.85;
    core1 *= 1.0 - core2 * (1.0 - front1) * 0.85;

    vec3 c1 = mix(C_DEEP, C_MAIN, dp1) + C_HOT * pow(dp1, 3.0) * 0.55;
    vec3 c2 = mix(C_DEEP, C_MAIN, dp2) + C_HOT * pow(dp2, 3.0) * 0.55;

    vec3 col = c1 * (core1 * (0.5 + 0.9 * dp1) + glow1 * 0.35 * (0.3 + 0.7 * dp1))
             + c2 * (core2 * (0.5 + 0.9 * dp2) + glow2 * 0.35 * (0.3 + 0.7 * dp2));

    // base-pair rungs: 10 per turn, vanish where the strands cross
    float cell = ph / (PI * 0.2);
    float rx = abs(fract(cell) - 0.5) * (PI * 0.2) / 6.0;
    float ymin = min(y1, -y1), ymax = max(y1, -y1);
    float inside = smoothstep(-0.004, 0.004, p.y - ymin)
                 * smoothstep(-0.004, 0.004, ymax - p.y);
    float rcore = smoothstep(thick * 0.65, thick * 0.22, rx) * inside;
    float sep = smoothstep(0.15, 0.55, (ymax - ymin) / (2.0 * amp));
    float h = hash(vec2(floor(cell), 17.0));   // per-pair tint variation
    vec3 rcol = mix(C_DEEP * 1.7, C_MAIN * 0.85, 0.3 + 0.5 * h);
    col += rcol * rcore * sep * 0.8;

    return col * bright;
}

void main() {
    vec2 p = vec2((qt_TexCoord0.x - 0.5) * uAspect, qt_TexCoord0.y - 0.5);
    float t = uTime;

    // gentle diagonal axis
    float a = -0.30;
    mat2 R = mat2(cos(a), -sin(a), sin(a), cos(a));
    vec2 q = R * p;

    // backdrop: red-black vignette + faint ambient bloom along the axis
    float r = length(p);
    vec3 col = mix(vec3(0.051, 0.033, 0.035), vec3(0.014, 0.008, 0.010),
                   smoothstep(0.15, 0.85, r));
    col += vec3(0.085, 0.012, 0.016) * exp(-q.y * q.y * 9.0);

    // far helix: parallax depth layer — smaller, slower, dim
    vec2 q2 = R * (p * 1.9 + vec2(0.35, 0.22));
    col += helix(q2, t * 0.21 + 2.7, 0.11, 0.012, 2600.0, 0.28);

    // main helix
    col += helix(q, t * 0.35, 0.17, 0.020, 900.0, 1.0);

    // drifting ember dust, sparse and twinkling
    vec2 g = p * 6.0 + vec2(t * 0.03, t * 0.012);
    vec2 id = floor(g);
    float h1 = hash(id);
    vec2 off = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
    float dd = length(fract(g) - 0.5 - off * 0.7);
    float tw = 0.5 + 0.5 * sin(t * (0.4 + h1 * 0.8) + h1 * 40.0);
    col += C_MAIN * exp(-dd * dd * 260.0) * tw * step(0.8, h1) * 0.10;

    // soft rolloff so stacked glow saturates gracefully, dither kills banding
    col = col / (1.0 + col * 0.35);
    col += (hash(qt_TexCoord0 * 971.7 + fract(t)) - 0.5) / 255.0;

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
