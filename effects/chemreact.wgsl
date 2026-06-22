// Chemreact — Gray-Scott reaction-diffusion in a fragment shader.
// U (activator) stored in RGB channels → drives the visual as warm cream/purple.
// V (inhibitor) stored in alpha channel → hidden from view, preserved for RD.
// Audio injects fresh chemical, modulating feed/kill/diffusion rates.

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
    let feed_base  = param(0u) * 0.06 + 0.02;    // feed rate (0.02–0.08)
    let kill_base  = param(1u) * 0.08 + 0.04;    // kill rate (0.04–0.12)
    let diff_a     = param(2u) * 0.5 + 0.5;      // diffusion A (0.5–1.0)
    let diff_b     = param(3u) * 0.3 + 0.2;      // diffusion B (0.2–0.5)
    let inject_str = param(4u) * 3.0 + 0.5;      // injection (0.5–3.5)

    // ── Audio → chemistry ──────────────────────────────────
    let feed = feed_base + loudness * 0.03 + centroid * 0.02;
    let kill = kill_base + centroid * 0.04 + (1.0 - flatness) * 0.02;
    let dA = diff_a * (0.8 + bass * 0.4);
    let dB = diff_b * (0.7 + brill * 0.6);

    // ── Read previous state ────────────────────────────────
    // R,G channels = U (visual + state), alpha = V (hidden state)
    let inv_res = 1.0 / res;
    let c  = feedback(uv);
    let l  = feedback(uv - vec2f(inv_res.x, 0.0));
    let r  = feedback(uv + vec2f(inv_res.x, 0.0));
    let u_  = feedback(uv + vec2f(0.0, inv_res.y));
    let d_  = feedback(uv - vec2f(0.0, inv_res.y));

    var U = c.r;  // stored in red (also == green == blue)
    var V = c.a;  // stored in alpha (hidden)

    // ── 5-point Laplacian ──────────────────────────────────
    let lapU = (l.r + r.r + u_.r + d_.r) - 4.0 * U;
    let lapV = (l.a + r.a + u_.a + d_.a) - 4.0 * V;

    // ── Gray-Scott step ────────────────────────────────────
    let react = U * V * V;
    U = clamp(U + dA * lapU - react + feed * (1.0 - U), 0.0, 1.0);
    V = clamp(V + dB * lapV + react - (kill + feed) * V, 0.0, 1.0);

    // ── Audio injection (background only — pattern dominates) ─
    // Inject U (not V) so audio gently feeds the existing patterns
    // rather than creating new foreground shapes.
    let centre_dist = length(uv - 0.5);

    // Beat: very soft wide centre glow on U
    let beat_inject = beat * exp(-centre_dist * 2.5) * inject_str * 0.06;
    U = clamp(U + beat_inject, 0.0, 1.0);

    // Onset: barely-there haze on U
    let drop_hash = fract(sin(dot(floor(uv * 35.0), vec2f(127.1, 311.7))) * 43758.5453);
    let drop = onset * smoothstep(0.6, 0.97, drop_hash) * inject_str * 0.04;
    U = clamp(U + drop, 0.0, 1.0);

    // RMS: slow global feed (keeps reaction alive, invisible)
    U = clamp(U + loudness * 0.003, 0.0, 1.0);

    // V decay: slow, prevents saturation
    V = V * 0.995;

    // Tiny V feed: keeps the reaction alive without visible artifacts
    V = clamp(V + 0.0005 + loudness * 0.001, 0.0, 1.0);

    // U recovery
    U = clamp(U + feed * (1.0 - U) * 0.1, 0.0, 1.0);

    // ── Visualize ──────────────────────────────────────────
    // U stored in RGB (R=G=B=U → clean grayscale, no artifacts).
    // V stored in alpha (hidden from view).
    // Warm cream tint via subtle R>G>B channel bias.
    // (centre_dist defined above in injection section)

    // Base: grayscale from U
    var rgb = vec3f(U);

    // Subtle warmth: boost red slightly, reduce blue
    rgb = rgb * vec3f(1.05, 0.95, 0.85);

    // Beat flash
    rgb += beat * vec3f(0.15, 0.12, 0.08) * exp(-centre_dist * 3.0);

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.6, centre_dist * 1.4) * 0.35;
    rgb *= vig;
    rgb = clamp(rgb, vec3f(0.0), vec3f(1.0));

    // ── Return: warm-tinted visual. R≈G≈B≈U preserves state. ──
    // Alpha carries V for the next Gray-Scott step.
    return vec4f(rgb, V * vig);
}
