// Chemreact — Organic reaction-diffusion drip patterns.
// Single-variable excitation-diffusion model: A diffuses, self-excites
// in a narrow range, and decays. Feedback stores A across frames.
// Audio injects fresh excitation on beat/onset, creating white organic
// blobs that grow, split, and flow like paint drips.

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let uv = frag_coord.xy / res;
    let t = u.time;

    // ── Audio ──────────────────────────────────────────────
    let loudness  = u.rms;
    let centroid  = u.centroid;
    let bass      = u.bass;
    let brill     = u.brilliance;
    let beat      = u.beat;
    let onset     = u.onset;
    let flatness  = u.flatness;
    let beat_phase = u.beat_phase;

    // ── Parameters ─────────────────────────────────────────
    let diffuse    = param(0u) * 0.6 + 0.4;       // diffusion rate (0.4–1.0)
    let growth     = param(1u) * 0.08 + 0.02;     // autocatalytic growth
    let decay      = param(2u) * 0.015 + 0.005;   // natural decay
    let inject_str = param(3u) * 2.5 + 0.5;       // injection strength
    let threshold  = param(4u) * 0.3 + 0.3;       // excitation threshold

    // ── Audio → dynamics ───────────────────────────────────
    let diff = diffuse * (0.7 + bass * 0.5);
    let grow = growth * (0.6 + loudness * 0.7);
    let dcy  = decay * (0.5 + centroid * 0.8);

    // ── Sample feedback (previous A field) ─────────────────
    let inv_res = 1.0 / res;
    let c  = feedback(uv);
    let l  = feedback(uv - vec2f(inv_res.x, 0.0));
    let r  = feedback(uv + vec2f(inv_res.x, 0.0));
    let u  = feedback(uv + vec2f(0.0, inv_res.y));
    let d  = feedback(uv - vec2f(0.0, inv_res.y));

    // Also sample diagonals for smoother diffusion
    let ul = feedback(uv + vec2f(-inv_res.x, inv_res.y));
    let ur = feedback(uv + vec2f( inv_res.x, inv_res.y));
    let dl = feedback(uv + vec2f(-inv_res.x,-inv_res.y));
    let dr = feedback(uv + vec2f( inv_res.x,-inv_res.y));

    var A = c.r;

    // ── 9-point Laplacian (smoother diffusion) ─────────────
    let neighbours = l.r + r.r + u.r + d.r;
    let diagonals  = ul.r + ur.r + dl.r + dr.r;
    let lap = neighbours * 0.2 + diagonals * 0.05 - A;

    // ── Excitation-diffusion step ──────────────────────────
    // A diffuses, grows autocatalytically in a sweet spot,
    // and decays when too high.
    let excitation = grow * A * (1.0 - A) * step(threshold, A);
    A = clamp(A + diff * lap + excitation - dcy * A, 0.0, 1.0);

    // ── Audio injection ────────────────────────────────────
    // (centre_dist defined once, used throughout)
    let centre_dist = length(uv - 0.5);
    let ring = exp(-abs(centre_dist - 0.15) * 20.0) * beat * inject_str * 0.4;
    A = clamp(A + ring, 0.0, 1.0);

    // Onset: scattered drops
    let drop_hash = fract(sin(dot(floor(uv * 25.0), vec2f(127.1, 311.7))) * 43758.5453);
    let drop = onset * step(0.94, drop_hash) * inject_str * 0.3;
    A = clamp(A + drop, 0.0, 1.0);

    // Quiet bass pulses: slow centre feed (keeps it alive)
    let bass_pulse = bass * (1.0 - loudness) * exp(-centre_dist * 2.5) * 0.008;
    A = clamp(A + bass_pulse, 0.0, 1.0);

    // ── Visualize ──────────────────────────────────────────
    // Store A directly in output (R=G=B=A). Next frame reads
    // it back as c.r. Linear — no state corruption.
    let bg    = vec3f(0.02, 0.015, 0.01);
    let cream = vec3f(0.94, 0.88, 0.72);
    let gold  = vec3f(0.85, 0.55, 0.18);
    let tint  = mix(cream, gold, centroid * 0.25);

    // A directly drives luminance — clean organic blobs
    let vig = 1.0 - smoothstep(0.5, 1.6, centre_dist * 1.4) * 0.35;
    let out = clamp(A * vig, 0.0, 1.0);
    var out_rgb = mix(bg, tint, out);
    out_rgb += beat * cream * 0.05 * exp(-centre_dist * 3.0);
    out_rgb = clamp(out_rgb, vec3f(0.0), vec3f(1.0));
    return vec4f(out_rgb, 1.0);
}
