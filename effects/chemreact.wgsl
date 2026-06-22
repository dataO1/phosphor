// Chemreact — Flow-field video feedback.
// Each frame, UV coordinates are warped by a noise field before
// sampling the previous frame. The warped feedback blends with
// the current frame. Audio modulates warp intensity and speed.
// Creates organic flowing landscapes — no reaction-diffusion blobs.

fn hash2(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2f(1.0, 0.0)), u.x),
        mix(hash2(i + vec2f(0.0, 1.0)), hash2(i + vec2f(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm2(p: vec2f) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var s = 1.0;
    for (var i = 0; i < 4; i++) {
        v += a * noise2(p * s);
        s *= 2.2;
        a *= 0.45;
    }
    return v;
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    var uv = frag_coord.xy / res;
    let aspect = res.x / res.y;
    let t = u.time;

    // ── Audio ──────────────────────────────────────────────
    let loudness = u.rms;
    let centroid = u.centroid;
    let bass     = u.bass;
    let brill    = u.brilliance;
    let flatness = u.flatness;

    // ── Parameters ─────────────────────────────────────────
    let warp_amt   = param(0u) * 0.15 + 0.02;    // warp intensity
    let flow_speed = param(1u) * 0.3 + 0.05;     // flow evolution speed
    let decay      = param(2u) * 0.15 + 0.82;    // feedback decay
    let contrast   = param(3u) * 0.8 + 0.6;      // contrast
    let detail     = param(4u) * 6.0 + 2.0;      // noise detail

    // ── Audio → dynamics ───────────────────────────────────
    let warp  = warp_amt * (0.4 + loudness * 1.2);
    let flow  = flow_speed * (0.5 + centroid * 1.0);
    let dcy   = decay * (0.95 + loudness * 0.05);

    // ── Flow field ─────────────────────────────────────────
    // Audio-modulated noise creates the warp vectors
    let n1 = fbm2(uv * detail + vec2f(t * flow, t * flow * 0.7));
    let n2 = fbm2(uv * detail + vec2f(t * flow * 0.8 + 5.0, t * flow * 0.6 + 3.0));
    let n3 = fbm2(uv * detail * 0.5 + vec2f(t * flow * 0.3, -t * flow * 0.4));

    // Warp UV: layered noise creates complex organic displacement
    let wx = (n1 - 0.5) * warp * 2.0 + (n3 - 0.5) * warp * 0.8;
    let wy = (n2 - 0.5) * warp * 2.0 + (n3 - 0.5) * warp * 0.8;

    var warped_uv = uv + vec2f(wx, wy);

    // ── Sample feedback at warped UV ───────────────────────
    var col = feedback(warped_uv).rgb;

    // Second feedback read at different warp (adds complexity)
    let wx2 = (noise2(uv * detail * 1.3 + t * flow * 0.5) - 0.5) * warp * 1.5;
    let wy2 = (noise2(uv * detail * 1.3 + t * flow * 0.5 + 3.0) - 0.5) * warp * 1.5;
    col += feedback(uv + vec2f(wx2, wy2)).rgb * 0.3;

    // ── Initial seed: organic noise pattern ────────────────
    if u.frame_index < 3.0 {
        let seed = fbm2(uv * 4.0 + t * 0.1) * 0.6 + 0.2;
        col = max(col, vec3f(seed));
    }

    // ── Decay ──────────────────────────────────────────────
    col *= dcy;

    // ── Contrast + colour ──────────────────────────────────
    // Subtle warm tint
    col = col * vec3f(1.08, 0.95, 0.82);
    // Contrast push
    col = (col - 0.08) * contrast;
    col = clamp(col, vec3f(0.0), vec3f(1.0));

    // ── Vignette ───────────────────────────────────────────
    let centre_dist = length(uv - 0.5);
    let vig = 1.0 - smoothstep(0.5, 1.6, centre_dist * 1.4) * 0.3;
    col *= vig;

    // ── Store V in alpha for unused channel ────────────────
    let state_val = dot(col, vec3f(0.33));
    return vec4f(col, state_val);
}
