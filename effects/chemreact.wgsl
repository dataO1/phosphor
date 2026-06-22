// Chemreact — Gray-Scott reaction-diffusion in a fragment shader.
// U (activator) stored in RGB channels → drives the visual as warm cream/purple.
// V (inhibitor) stored in alpha channel → hidden from view, preserved for RD.
// Audio injects fresh chemical, modulating feed/kill/diffusion rates.

@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let uv = frag_coord.xy / res;

    // ── Audio ──────────────────────────────────────────────
    let loudness = u.rms;
    let centroid = u.centroid;
    let bass     = u.bass;
    let brill    = u.brilliance;
    let flatness = u.flatness;

    // ── Parameters ─────────────────────────────────────────
    let feed_base  = param(0u) * 0.07 + 0.03;    // feed rate (0.03–0.10)
    let kill_base  = param(1u) * 0.06 + 0.05;    // kill rate (0.05–0.11)
    let diff_a     = param(2u) * 0.5 + 0.6;      // diffusion A (0.6–1.1)
    let diff_b     = param(3u) * 0.3 + 0.25;     // diffusion B (0.25–0.55)
    let inject_str = param(4u) * 3.0 + 0.5;      // injection (0.5–3.5)

    // ── Audio → chemistry ──────────────────────────────────
    // Spatial variation: noise-based perturbation so patterns
    // differ across the screen.
    let pos_hash = fract(sin(dot(uv * 3.0, vec2f(127.1, 311.7))) * 43758.5453);
    let feed_var = (pos_hash - 0.5) * 0.015;
    let kill_var = (pos_hash - 0.5) * 0.01;
    let feed = feed_base + loudness * 0.03 + centroid * 0.02 + feed_var;
    let kill = kill_base + centroid * 0.04 + (1.0 - flatness) * 0.02 + kill_var;
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

    // ── Initial seed: kickstart the reaction on first frames ─
    // Without this, the RD field starts from black and takes
    // minutes to bootstrap.
    let centre_dist = length(uv - 0.5);
    if u.frame_index < 5.0 {
        // Three asymmetric seeds for richer starting patterns
        let s1 = exp(-length(uv - vec2f(0.45, 0.48)) * 25.0);
        let s2 = exp(-length(uv - vec2f(0.55, 0.52)) * 20.0);
        let s3 = exp(-length(uv - vec2f(0.50, 0.45)) * 22.0);
        let seed = max(max(s1 * 0.8, s2 * 0.6), s3 * 0.5);
        U = max(U, seed);
        V = max(V, seed * 0.3);
    }

    // ── Audio: barely-there background feed only ────────────
    // Audio just gently sustains the reaction.
    U = clamp(U + loudness * inject_str * 0.003, 0.0, 1.0);

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
    // Visual: sharper contrast, less blob-like
    let U_vis = smoothstep(0.06, 0.55, U);
    // R = U (state), G,B = visual (won't be read as state)
    var rgb = vec3f(U, U_vis * 0.95, U_vis * 0.85);

    // Subtle warmth: boost red slightly, reduce blue
    rgb = rgb * vec3f(1.05, 0.95, 0.85);

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.6, centre_dist * 1.4) * 0.35;
    rgb *= vig;
    rgb = clamp(rgb, vec3f(0.0), vec3f(1.0));

    // ── Return: warm-tinted visual. R≈G≈B≈U preserves state. ──
    // Alpha carries V for the next Gray-Scott step.
    return vec4f(rgb, V * vig);
}
