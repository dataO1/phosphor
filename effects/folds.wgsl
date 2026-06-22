// Folds — Deep video-feedback kaleidoscope.
// Macro-scale morphing via sustained audio features:
//   centroid → fold count, flatness → distortion, flux → secondary fold mix
//   beat_phase → cyclical breathing, bpm → rotation speed
// Micro-scale: kick/onset → flash, beat → centre pulse
// Warm gold + ivory palette on charcoal.

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let aspect = res.x / res.y;
    let uv = frag_coord.xy / res;
    let t = u.time;

    // ── Audio: sustained (macro morphing) ──────────────────
    let loudness   = u.rms;           // overall energy
    let centroid   = u.centroid;      // spectral brightness (dark↔bright)
    let flux       = u.flux;          // rate of spectral change
    let flatness   = u.flatness;      // noise vs tone (noisy↔tonal)
    let bpm        = u.bpm * 300.0;   // actual BPM (60–200)
    let beat_phase = u.beat_phase;    // 0→1 sawtooth at tempo
    let rolloff    = u.rolloff;       // high-frequency cutoff

    // ── Audio: transient (micro reactivity) ────────────────
    let bass     = u.bass;
    let low_mid  = u.low_mid;
    let mid      = u.mid;
    let up_mid   = u.upper_mid;
    let pres     = u.presence;
    let brill    = u.brilliance;
    let beat     = u.beat;
    let onset    = u.onset;

    // ── User parameters ────────────────────────────────────
    let folds_base  = param(0u) * 9.0 + 3.0;       // base symmetry (3–12)
    let rotation    = param(1u) * 0.08 + 0.015;    // spin per frame
    let zoom        = param(2u) * 0.06 + 0.92;     // scale per pass
    let complexity  = param(3u) * 6.0 + 2.0;       // secondary folds
    let distortion  = param(4u) * 0.04;            // warp amount

    // ═══════════════════════════════════════════════════════
    // MACRO MORPHING — sustained audio reshapes the geometry
    // ═══════════════════════════════════════════════════════

    // Symmetry: brighter + more tonal = more folds
    let folds = folds_base + centroid * 5.0 + (1.0 - flatness) * 4.0;

    // Rotation: BPM-synced baseline + centroid boost
    let tempo_factor = (bpm - 60.0) / 140.0;  // 0 at 60bpm, 1 at 200bpm
    let rot = rotation * (1.0 + loudness * 2.5 + centroid * 1.5 + tempo_factor * 1.5);

    // Zoom breathing: beat_phase creates a slow pulse at BPM
    let breathe = 1.0 + sin(beat_phase * 6.28318) * 0.015 * loudness;
    let sc = zoom * breathe * (1.0 + bass * 0.015);

    // Secondary fold mix: flux drives how much the second symmetry intrudes
    let sec_fold_mix = 0.2 + flux * 0.5 + centroid * 0.2;

    // Distortion: flatness controls organic warp (noisy = warped)
    let warp = distortion * (0.3 + flatness * 1.4);

    // Origin drift: cyclical at BPM, amplitude from loudness
    let ox = sin(t * 0.13 + beat_phase * 6.28318) * 0.06 * loudness;
    let oy = cos(t * 0.17 + beat_phase * 3.5) * 0.06 * loudness;

    // ═══════════════════════════════════════════════════════
    // PALETTE
    // ═══════════════════════════════════════════════════════
    let bg_col    = vec3f(0.04, 0.03, 0.02);
    let gold      = vec3f(0.95, 0.62, 0.18);
    let ivory     = vec3f(0.92, 0.85, 0.72);
    let copper    = vec3f(0.82, 0.35, 0.12);
    let highlight = vec3f(0.98, 0.95, 0.88);

    // ═══════════════════════════════════════════════════════
    // FEEDBACK TRANSFORM #1 — primary spiral
    // ═══════════════════════════════════════════════════════

    var p = uv - vec2f(0.5 + ox, 0.5 + oy);
    p.x *= aspect;

    let r = length(p);
    var a = atan2(p.y, p.x);

    // Primary N-fold kaleidoscope
    let wedge = 6.28318 / folds;
    a = abs(a);
    a = a - wedge * floor(a / wedge);
    a = min(a, wedge - a);

    // Apply rotation
    a = a + t * rot + centroid * 2.0;

    // Secondary folding (mixed based on flux)
    let wedge2 = 6.28318 / complexity;
    let a_folded = min(abs(a) - wedge2 * floor(abs(a) / wedge2), wedge2 - (abs(a) - wedge2 * floor(abs(a) / wedge2)));
    a = mix(a, a_folded, sec_fold_mix);

    // Back to cartesian
    let r_scaled = r / sc;
    p = vec2f(cos(a) * r_scaled, sin(a) * r_scaled);
    var fuv = p / vec2f(aspect, 1.0) + 0.5;

    // ── Read feedback #1 ───────────────────────────────────
    var col = feedback(fuv).rgb;

    // ── Feedback #2: deeper zoom (visible nesting) ─────────
    var p2 = (uv - 0.5) * vec2f(aspect, 1.0);
    let r2 = length(p2);
    var a4 = atan2(p2.y, p2.x);
    a4 = abs(a4);
    a4 = a4 - wedge * floor(a4 / wedge);
    a4 = min(a4, wedge - a4);
    a4 = a4 + t * rot * 1.3;
    p2 = vec2f(cos(a4) * r2 / (sc * sc), sin(a4) * r2 / (sc * sc));
    let fuv2 = p2 / vec2f(aspect, 1.0) + 0.5;
    col += feedback(fuv2).rgb * 0.2;

    // ── Organic distortion ─────────────────────────────────
    let wx = sin(fuv.y * 12.0 + t * 0.3) * cos(fuv.x * 8.0 + t * 0.25) * warp;
    let wy = cos(fuv.x * 10.0 + t * 0.35) * sin(fuv.y * 14.0 + t * 0.2) * warp;
    let warped = feedback(fuv + vec2f(wx, wy)).rgb;
    col = mix(col, warped, 0.10);

    // ── Decay to background (prevents blowout) ─────────────
    let decay = 0.88 + loudness * 0.04;
    col = col * decay + bg_col * (1.0 - decay);

    // Centre glow
    let cd = 1.0 - length(uv - 0.5) * 2.2;
    col += bg_col * max(0.0, cd) * 0.015;

    // Gentle contrast
    col = clamp((col - 0.015) * 1.04, vec3f(0.0), vec3f(1.0));

    // ═══════════════════════════════════════════════════════
    // STRUCTURAL RAYS — audio-driven, feed into the loop
    // ═══════════════════════════════════════════════════════
    let bands = array<f32, 6>(bass, low_mid, mid, up_mid, pres, brill);
    let ray_n = u32(complexity) * 4u + 4u;

    var rays = vec3f(0.0);

    for (var i = 0u; i < ray_n; i++) {
        let fi = f32(i);
        let band = bands[i % 6u];
        if band < 0.015 { continue; }

        let ba = fi / f32(ray_n) * 6.28318;
        let wobble = sin(fi * 1.17 + t * 0.4 + band * 3.0) * band * 0.04;
        let ra = ba + wobble;

        let rx = uv.x - 0.5;
        let ry = (uv.y - 0.5) * aspect;
        let dist = abs(rx * sin(ra) - ry * cos(ra));

        let ray_len = 0.08 + band * 0.65 + onset * 0.08;
        let along = rx * cos(ra) + ry * sin(ra);
        let radial_fade = 1.0 - smoothstep(0.0, ray_len, abs(along));
        if radial_fade < 0.01 { continue; }

        let w = param(4u) * 0.004 + 0.0008;
        let intensity = exp(-(dist * dist) / (w * w * (0.3 + band * 0.7)))
                      * band * radial_fade * 0.22;
        if intensity < 0.0003 { continue; }

        let col_mix = mix(copper, gold, band);
        rays += mix(col_mix, ivory, intensity * 0.5) * intensity;
    }

    // ── Blend rays on top (not pure additive — prevents blowout) ──
    let ray_brightness = dot(rays, vec3f(0.33));
    col = mix(col, col + rays, 0.6);

    // ═══════════════════════════════════════════════════════
    // MICRO: beat/onset transients
    // ═══════════════════════════════════════════════════════
    let centre_dist = length(uv - 0.5);
    col += beat * exp(-centre_dist * 5.0) * highlight * 0.10;

    // Vignette
    let vig = 1.0 - smoothstep(0.7, 1.6, centre_dist * 1.4) * 0.3;
    col *= vig;

    // Hard clamp — no blowout
    col = clamp(col, vec3f(0.0), vec3f(1.0));

    return vec4f(col, 1.0);
}
