// Glow Particles — Audio-reactive glowing particles with slow circular drift.
// Louder = faster motion, more colorful. Frequency bands map to color.
// Uses feedback for motion trails.

fn hash2(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec2f) -> vec3f {
    return vec3f(
        hash2(p),
        hash2(p + vec2f(19.19, 59.31)),
        hash2(p + vec2f(87.43, 13.71)),
    );
}

// Simple HSV → RGB (h in 0-1, s/v in 0-1)
fn hsv2rgb(c: vec3f) -> vec3f {
    let h = c.x * 6.0;
    let s = c.y;
    let v = c.z;
    let sector = u32(floor(h));
    let f = h - f32(sector);
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    switch sector {
        case 0u: { return vec3f(v, t, p); }
        case 1u: { return vec3f(q, v, p); }
        case 2u: { return vec3f(p, v, t); }
        case 3u: { return vec3f(p, q, v); }
        case 4u: { return vec3f(t, p, v); }
        default: { return vec3f(v, p, q); }
    }
}

fn effect(uv: vec2f) -> vec4f {
    let res = u.resolution;
    let aspect = res.x / res.y;
    let t = u.time;
    let dt = u.delta_time;

    // ── Audio ──────────────────────────────────────────────
    let loudness = u.rms;                        // overall volume 0–1
    let bass     = u.bass;                       // 60-250 Hz
    let low_mid  = u.low_mid;                    // 250-500 Hz
    let mid      = u.mid;                        // 500-2000 Hz
    let high     = u.presence + u.brilliance;    // 4-20 kHz
    let centroid = u.centroid;                   // spectral brightness
    let flux     = u.flux;                       // rate of change
    let beat     = u.beat;                       // 1.0 on beat

    // ── Parameters ─────────────────────────────────────────
    let particle_count = param(0u) * 140.0 + 20.0;   // 20–160 particles
    let glow_size      = param(1u) * 0.015 + 0.003;  // glow radius
    let base_speed     = param(2u) * 0.4 + 0.05;     // orbit speed
    let audio_drive    = param(3u) * 4.0 + 0.5;      // audio → motion multiplier
    let trail_decay    = param(4u) * 0.3 + 0.82;     // feedback trail fade

    // ── Color from audio ───────────────────────────────────
    // Low frequencies warm (red/orange), high frequencies cool (blue/violet)
    let hue = 0.05 + bass * 0.15 + mid * 0.25 + high * 0.35;
    let saturation = 0.3 + loudness * 0.7;
    let value_boost = 0.4 + loudness * 0.6 + beat * 0.4;

    // ── Render particles ───────────────────────────────────
    var col = vec3f(0.0);
    let n = u32(particle_count);

    for (var i = 0u; i < n; i += 1u) {
        let fi = f32(i);

        // Per-particle random seeds
        let seed0 = hash2(vec2f(fi, 0.13));
        let seed1 = hash2(vec2f(fi, 7.91));
        let seed2 = hash2(vec2f(fi, 43.27));
        let seed3 = hash2(vec2f(fi, 99.01));

        // ── Base position (spread evenly-ish across screen) ─
        let px = (seed0 - 0.5) * 2.0 * aspect;
        let py = (seed1 - 0.5) * 2.0;

        // ── Slow circular orbit (base motion) ──────────────
        let orbit_r    = 0.02 + seed2 * 0.12;           // orbit radius
        let orbit_freq = base_speed * (0.3 + seed3 * 0.7); // unique per particle
        let orbit_phase = seed1 * 6.28318;                 // starting angle

        // Audio boosts orbit speed
        let speed_mult = 1.0 + loudness * audio_drive;
        let angle = orbit_phase + t * orbit_freq * speed_mult;

        // ── Audio jitter (louder = more displacement) ─────
        let jitter_scale = loudness * audio_drive * 0.15;
        let jx = (hash2(vec2f(fi, t * 1.7 + 0.3)) - 0.5) * jitter_scale;
        let jy = (hash2(vec2f(fi, t * 1.9 + 0.7)) - 0.5) * jitter_scale;

        // Beat: quick outward burst
        let beat_push = beat * loudness * 0.08;
        let bx = cos(orbit_phase) * beat_push;
        let by = sin(orbit_phase) * beat_push;

        // ── Final particle position ────────────────────────
        let final_x = px + cos(angle) * orbit_r + jx + bx;
        let final_y = py + sin(angle) * orbit_r + jy + by;

        // ── Distance from current pixel to particle ────────
        let dx = uv.x * aspect - final_x;
        let dy = uv.y - final_y;
        let dist2 = dx * dx + dy * dy;

        // ── Glow (Gaussian falloff) ────────────────────────
        let g = glow_size * (0.5 + loudness * 0.5);
        let particle_brightness = exp(-dist2 / (g * g));

        if particle_brightness < 0.001 { continue; }

        // ── Per-particle color variation ───────────────────
        let p_hue = fract(hue + seed2 * 0.4 - 0.2);
        let p_val = particle_brightness * value_boost * (0.6 + seed3 * 0.4);
        let p_col = hsv2rgb(vec3f(p_hue, saturation, p_val));

        col += p_col;
    }

    // ── Feedback trails ────────────────────────────────────
    let fb = feedback(uv);
    col += fb.rgb * trail_decay;

    // ── Subtle vignette ────────────────────────────────────
    let vig = 1.0 - smoothstep(0.4, 1.4, length(uv - 0.5) * 1.5) * 0.3;
    col *= vig;

    return vec4f(col, 1.0);
}
