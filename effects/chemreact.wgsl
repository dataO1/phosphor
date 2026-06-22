// Chemreact — Gray-Scott reaction-diffusion in a fragment shader.
// The feedback texture stores U (R) and V (G) chemical fields.
// Each frame computes one Gray-Scott step on the entire screen.
// Audio modulates feed/kill rates, shifting between spots/stripes/labyrinths.
// Beat/onset inject fresh V chemical, creating organic white drip patterns.

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let uv = frag_coord.xy / res;
    let t = u.time;

    // ── Audio ──────────────────────────────────────────────
    let loudness = u.rms;
    let centroid = u.centroid;
    let bass     = u.bass;
    let brill    = u.brilliance;
    let beat     = u.beat;
    let onset    = u.onset;
    let flatness = u.flatness;

    // ── Parameters ─────────────────────────────────────────
    // Feed rate: controls new A growth. Low = spots, high = stripes/chaos.
    let feed_base  = param(0u) * 0.06 + 0.02;    // 0.02–0.08
    // Kill rate: controls B removal. Low = dense, high = sparse.
    let kill_base  = param(1u) * 0.08 + 0.04;    // 0.04–0.12
    // Diffusion A
    let diff_a     = param(2u) * 0.5 + 0.5;      // 0.5–1.0
    // Diffusion B
    let diff_b     = param(3u) * 0.3 + 0.2;      // 0.2–0.5
    // Injection strength
    let inject_str = param(4u) * 3.0 + 0.5;      // 0.5–3.5

    // ── Audio → chemistry modulation ──────────────────────
    // Louder = more feed (spots → stripes), brighter centroid = more kill
    let feed = feed_base + loudness * 0.03 + centroid * 0.02;
    let kill = kill_base + centroid * 0.04 + (1.0 - flatness) * 0.02;
    let dA = diff_a * (0.8 + bass * 0.4);
    let dB = diff_b * (0.7 + brill * 0.6);

    // ── Sample feedback at centre + 4 neighbours ───────────
    let inv_res = 1.0 / res;
    let centre = feedback(uv);
    let left   = feedback(uv - vec2f(inv_res.x, 0.0));
    let right  = feedback(uv + vec2f(inv_res.x, 0.0));
    let up     = feedback(uv + vec2f(0.0, inv_res.y));
    let down   = feedback(uv - vec2f(0.0, inv_res.y));

    var A = centre.r;
    var B = centre.g;

    // ── 5-point Laplacian ──────────────────────────────────
    let lapA = (left.r + right.r + up.r + down.r) - 4.0 * A;
    let lapB = (left.g + right.g + up.g + down.g) - 4.0 * B;

    // ── Gray-Scott reaction step ───────────────────────────
    let react = A * B * B;
    A = clamp(A + dA * lapA - react + feed * (1.0 - A), 0.0, 1.0);
    B = clamp(B + dB * lapB + react - (kill + feed) * B, 0.0, 1.0);

    // ── Audio injection: seed B on beat/onset ──────────────
    // Centre pulse on beat
    let centre_dist = length(uv - 0.5);
    let beat_inject = beat * exp(-centre_dist * 6.0) * inject_str * 0.3;
    B = clamp(B + beat_inject, 0.0, 1.0);

    // Scattered drops on onset (hash-based)
    let drop_hash = fract(sin(dot(floor(uv * 20.0), vec2f(127.1, 311.7))) * 43758.5453);
    let onset_inject = onset * step(0.92, drop_hash) * inject_str * 0.25;
    B = clamp(B + onset_inject, 0.0, 1.0);

    // ── Subtle B decay (prevents saturation) ───────────────
    B = B * 0.995;

    // ── Ensure A recovers in areas with no B ───────────────
    A = clamp(A + feed * (1.0 - A) * 0.1, 0.0, 1.0);

    // ── Visualize ──────────────────────────────────────────
    // U field (A) = organic white drips/blobs.
    // Warm cream tint, with subtle variation from centroid.
    let warmth = 0.82 + centroid * 0.13;
    let cream = vec3f(warmth, warmth * 0.92, warmth * 0.72);
    let u_vis = smoothstep(0.05, 0.95, A);
    var rgb = cream * u_vis * 1.08;
    let bg = vec3f(0.025, 0.018, 0.01);
    rgb += bg * (1.0 - u_vis);

    // Beat: subtle brightness pulse
    rgb += beat * cream * 0.06 * exp(-centre_dist * 4.0);

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, centre_dist * 1.3) * 0.4;
    rgb *= vig;
    rgb = clamp(rgb, vec3f(0.0), vec3f(1.0));

    // ── Return: R=A (state), G=B (state), B=visual luminance ──
    // Next frame's feedback() reads R,G as A,B for Gray-Scott.
    return vec4f(A * vig, B * vig, dot(rgb, vec3f(0.3, 0.6, 0.1)), 1.0);
}
