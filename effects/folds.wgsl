// Folds — Deep video-feedback kaleidoscope.
// Each frame: the previous image is rotated, scaled down, and folded
// back into itself. The transform chains frame-over-frame, creating
// visible nested spirals that recede into the centre.
//
// Two feedback reads at different scales make the recursion obvious.
// A second folding pass breaks the circular symmetry into sharp
// geometric fragments. Warm gold palette on deep charcoal.

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let aspect = res.x / res.y;
    let uv = frag_coord.xy / res;
    let t = u.time;

    // ── Audio ──────────────────────────────────────────────
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
    let flux     = u.flux;

    // ── Parameters ─────────────────────────────────────────
    let folds       = param(0u) * 9.0 + 3.0;       // primary symmetry (3–12)
    let rotation    = param(1u) * 0.08 + 0.015;    // spin per frame
    let zoom        = param(2u) * 0.06 + 0.92;     // scale per pass (tighter)
    let complexity  = param(3u) * 6.0 + 2.0;       // secondary fold count
    let distortion  = param(4u) * 0.04;            // organic warp amount

    // ═══════════════════════════════════════════════════════
    // PALETTE: warm gold + ivory on charcoal
    // ═══════════════════════════════════════════════════════
    let bg_col    = vec3f(0.04, 0.03, 0.02);    // deep charcoal
    let gold      = vec3f(0.95, 0.62, 0.18);    // warm gold
    let ivory     = vec3f(0.92, 0.85, 0.72);    // cream
    let copper    = vec3f(0.82, 0.35, 0.12);    // burnt orange
    let highlight = vec3f(0.98, 0.95, 0.88);    // near-white

    // ═══════════════════════════════════════════════════════
    // FEEDBACK TRANSFORM #1 — primary spiral
    // ═══════════════════════════════════════════════════════

    // Shift origin to centre (with slight audio-driven offset)
    var p = uv - vec2f(
        0.5 + sin(t * 0.17) * 0.04 * loudness,
        0.5 + cos(t * 0.13) * 0.04 * loudness
    );
    p.x *= aspect;

    // Polar coordinates
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Primary N-fold kaleidoscope
    let wedge = 6.28318 / folds;
    a = abs(a);
    a = a - wedge * floor(a / wedge);
    a = min(a, wedge - a);

    // Rotation — audio-accelerated
    let rot = rotation * (1.0 + loudness * 4.0 + centroid * 3.0);
    a = a + t * rot + centroid * 2.0;

    // Scale down — creates the visible nesting
    let sc = zoom * (1.0 + bass * 0.02);

    // Secondary folding at a different symmetry (breaks circular monotony)
    let wedge2 = 6.28318 / complexity;
    let a2 = abs(a);
    let a3 = a2 - wedge2 * floor(a2 / wedge2);
    a = mix(a, min(a3, wedge2 - a3), 0.35 + loudness * 0.3);

    // Back to cartesian for feedback sample
    let r_scaled = r / sc;
    p = vec2f(cos(a) * r_scaled, sin(a) * r_scaled);
    var fuv = p / vec2f(aspect, 1.0) + 0.5;

    // ── Read feedback at transformed UV ────────────────────
    var col = feedback(fuv).rgb;

    // ── Second feedback read at deeper zoom (visible nesting) ──
    var p2 = (uv - 0.5) * vec2f(aspect, 1.0);
    let r2 = length(p2);
    var a4 = atan2(p2.y, p2.x);
    a4 = abs(a4);
    a4 = a4 - wedge * floor(a4 / wedge);
    a4 = min(a4, wedge - a4);
    a4 = a4 + t * rot * 1.3;
    let sc2 = sc * sc;  // square the zoom for nested copies
    p2 = vec2f(cos(a4) * r2 / sc2, sin(a4) * r2 / sc2);
    let fuv2 = p2 / vec2f(aspect, 1.0) + 0.5;
    col += feedback(fuv2).rgb * 0.45;

    // ── Organic distortion (subtle domain warp) ────────────
    let warp_x = sin(fuv.y * 12.0 + t * 0.3) * cos(fuv.x * 8.0 + t * 0.25) * distortion;
    let warp_y = cos(fuv.x * 10.0 + t * 0.35) * sin(fuv.y * 14.0 + t * 0.2) * distortion;
    let warped = feedback(fuv + vec2f(warp_x, warp_y)).rgb;
    col = mix(col, warped, 0.25);

    // ── Decay toward charcoal background ───────────────────
    let decay = 0.92 + loudness * 0.03;
    col = col * decay + bg_col * (1.0 - decay);

    // ── Subtle bloom-like centre accumulation ──────────────
    let centre = 1.0 - length(uv - 0.5) * 2.2;
    col += bg_col * max(0.0, centre) * 0.02;

    // Contrast
    col = (col - 0.03) * 1.08;
    col = clamp(col, vec3f(0.0), vec3f(1.0));

    // ═══════════════════════════════════════════════════════
    // STRUCTURAL LINES — audio-driven geometric rays
    // ═══════════════════════════════════════════════════════
    let bands = array<f32, 6>(bass, low_mid, mid, up_mid, pres, brill);
    let line_n = u32(complexity) * 4u + 4u;

    var lines = vec3f(0.0);

    for (var i = 0u; i < line_n; i++) {
        let fi = f32(i);
        let band = bands[i % 6u];
        if band < 0.015 { continue; }

        // Ray angle — even spacing + audio wobble
        let ba = fi / f32(line_n) * 6.28318;
        let wobble = sin(fi * 1.17 + t * 0.4 + band * 3.0) * band * 0.04;
        let ra = ba + wobble;

        // Distance from pixel to this ray
        let rx = uv.x - 0.5;
        let ry = (uv.y - 0.5) * aspect;
        let dist = abs(rx * sin(ra) - ry * cos(ra));

        // Ray intensity — brighter near centre, audio-driven
        let ray_len = 0.1 + band * 0.7 + onset * 0.1;
        let along = rx * cos(ra) + ry * sin(ra);
        let radial_fade = 1.0 - smoothstep(0.0, ray_len, abs(along));

        if radial_fade < 0.01 { continue; }

        let w = param(4u) * 0.005 + 0.001;
        let intensity = exp(-(dist * dist) / (w * w * (0.3 + band * 0.7)))
                      * band * radial_fade * 0.5;

        if intensity < 0.0005 { continue; }

        // Single-palette colour: gold tint with amplitude-driven brightness
        let col_mix = mix(copper, gold, band);
        lines += mix(col_mix, ivory, intensity * 0.6) * intensity;
    }

    // ═══════════════════════════════════════════════════════
    // COMPOSITE
    // ═══════════════════════════════════════════════════════
    col += lines;

    // Beat: brief centre pulse in highlight colour
    let centre_dist = length(uv - 0.5);
    col += beat * exp(-centre_dist * 5.0) * highlight * 0.25;

    // Subtle vignette
    let vig = 1.0 - smoothstep(0.7, 1.6, centre_dist * 1.4) * 0.3;
    col *= vig;

    col = clamp(col, vec3f(0.0), vec3f(1.2));

    return vec4f(col, 1.0);
}
