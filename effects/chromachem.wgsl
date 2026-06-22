// Chromachem — Audio-driven chromatic chemistry.
// Seven frequency bands inject colour into a feedback-based
// diffusion field. The result is an evolving organic painting
// that reacts to the music. No particles — pure feedback magic.

fn hash2(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

fn hsv2rgb(c: vec3f) -> vec3f {
    let h = c.x * 6.0;
    let s = c.y;
    let v = c.z;
    let sec = u32(floor(h));
    let f = h - f32(sec);
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    switch sec {
        case 0u: { return vec3f(v, t, p); }
        case 1u: { return vec3f(q, v, p); }
        case 2u: { return vec3f(p, v, t); }
        case 3u: { return vec3f(p, q, v); }
        case 4u: { return vec3f(t, p, v); }
        default: { return vec3f(v, p, q); }
    }
}

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let uv = frag_coord.xy / res;
    let aspect = res.x / res.y;
    let t = u.time;

    // ── Audio ──────────────────────────────────────────────
    let sub      = u.sub_bass;
    let bass     = u.bass;
    let low_mid  = u.low_mid;
    let mid      = u.mid;
    let up_mid   = u.upper_mid;
    let pres     = u.presence;
    let brill    = u.brilliance;
    let loudness = u.rms;
    let centroid = u.centroid;
    let beat     = u.beat;
    let onset    = u.onset;

    // ── Parameters ─────────────────────────────────────────
    let diffusion  = param(0u) * 0.08 + 0.90;   // feedback decay (0.90–0.98)
    let inject_str = param(1u) * 2.0 + 0.3;     // injection intensity
    let spot_size  = param(2u) * 0.3 + 0.05;    // injection spot radius
    let warp_amt   = param(3u) * 0.015;         // subtle domain warp
    let colour_sat = param(4u) * 0.5 + 0.5;     // colour saturation

    // ── Read feedback (previous frame) ─────────────────────
    var col = feedback(uv).rgb;

    // Subtle domain warp on the feedback read — creates
    // organic flow instead of static diffusion.
    let warp_x = (hash2(uv * 3.0 + fract(t * 0.1)) - 0.5) * warp_amt;
    let warp_y = (hash2(uv * 3.0 + fract(t * 0.1 + 5.0)) - 0.5) * warp_amt;
    let wuv = uv + vec2f(warp_x, warp_y);
    col = mix(col, feedback(wuv).rgb, 0.3);

    // ── Diffuse — blend with neighbours via tiny offsets ──
    let d = 0.002;
    let blur = (
        feedback(uv + vec2f( d,  0.0)).rgb +
        feedback(uv + vec2f(-d,  0.0)).rgb +
        feedback(uv + vec2f( 0.0, d)).rgb +
        feedback(uv + vec2f( 0.0,-d)).rgb
    ) * 0.25;
    col = mix(col, blur, 0.15);

    // Decay
    col *= diffusion;

    // ── Inject colour spots from each frequency band ───────
    let bands = array<f32, 7>(sub, bass, low_mid, mid, up_mid, pres, brill);
    let hues  = array<f32, 7>(
        0.0,    // sub_bass  → red
        0.07,   // bass      → orange
        0.15,   // low_mid   → yellow
        0.35,   // mid       → green
        0.55,   // upper_mid → cyan
        0.68,   // presence  → blue
        0.82    // brilliance → violet
    );

    for (var i = 0u; i < 7u; i++) {
        let amp = bands[i];
        if amp < 0.02 { continue; }

        // Each band's injection point drifts slowly,
        // with a unique Lissajous orbit.
        let fi = f32(i);
        let ox = sin(t * (0.07 + fi * 0.03) + fi * 1.3) * 0.35;
        let oy = cos(t * (0.09 + fi * 0.02) + fi * 2.1) * 0.35;
        let centre = vec2f(0.5 + ox, 0.5 + oy);

        // Distance to injection point (aspect-corrected)
        let dx = uv.x - centre.x;
        let dy = (uv.y - centre.y) * aspect;
        let dist2 = dx * dx + dy * dy;

        // Glow size scales with amplitude
        let radius = spot_size * (0.6 + amp * 0.8);
        let glow = exp(-dist2 / (radius * radius)) * amp * inject_str;

        if glow < 0.001 { continue; }

        // Per-band hue, shifted by spectral centroid
        let h = fract(hues[i] + centroid * 0.12);
        let s = colour_sat * (0.5 + amp * 0.5);
        let v = glow;
        let inj_col = hsv2rgb(vec3f(h, s, v));

        col += inj_col * glow;
    }

    // ── Beat: full-frame flash ─────────────────────────────
    col += beat * loudness * 0.12;

    // ── Onset: edge brightening ────────────────────────────
    let edge_dist = length(uv - 0.5) * 2.0;
    col += onset * (1.0 - edge_dist) * 0.06;

    // ── Vignette ───────────────────────────────────────────
    let vig = 1.0 - smoothstep(0.7, 1.6, edge_dist) * 0.4;
    col *= vig;

    // Clamp to prevent additive blowout
    col = clamp(col, vec3f(0.0), vec3f(1.5));

    return vec4f(col, 1.0);
}
