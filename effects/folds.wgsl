// Folds — Intricate feedback kaleidoscope with audio-reactive line geometry.
// Classic video-feedback technique (Inigo Quilez): each frame, the previous
// image is rotated, scaled, and kaleidoscopically folded back onto itself.
// Thin spectral lines are drawn on top, then the whole thing feeds back.
// Result: sharp, endlessly complex spiraling mandala patterns.

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
    let aspect = res.x / res.y;
    let uv = frag_coord.xy / res;
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
    let flux     = u.flux;

    // ── Parameters ─────────────────────────────────────────
    let folds       = param(0u) * 10.0 + 2.0;      // kaleidoscope symmetry (2–12)
    let rotation    = param(1u) * 0.06 + 0.01;     // rotation per frame
    let zoom        = param(2u) * 0.03 + 0.97;     // scale per feedback pass
    let line_count  = param(3u) * 80.0 + 8.0;      // spectral lines (8–88)
    let line_width  = param(4u) * 0.004 + 0.0008;  // line thickness

    // ═══════════════════════════════════════════════════════
    // KALEIDOSCOPIC FEEDBACK TRANSFORM
    // ═══════════════════════════════════════════════════════

    // Center origin, aspect-correct
    var p = (uv - 0.5) * vec2f(aspect, 1.0);

    // Convert to polar
    let radius = length(p);
    var angle = atan2(p.y, p.x);

    // N-fold symmetry: fold angle into a wedge, mirror within
    let wedge = 6.28318 / folds;
    angle = abs(angle);                          // mirror across x-axis
    angle = angle - wedge * floor(angle / wedge); // wrap into [0, wedge)
    angle = min(angle, wedge - angle);           // mirror within wedge

    // Flux dynamically changes the fold count
    let dynamic_folds = folds + flux * 4.0;
    let dynamic_wedge = 6.28318 / dynamic_folds;
    angle = min(angle, dynamic_wedge - angle * (wedge / dynamic_wedge));

    // Rotation: audio accelerates spin
    let rot_speed = rotation * (1.0 + loudness * 3.0 + centroid * 2.0);
    angle = angle + t * rot_speed + centroid * 1.5;

    // Scale: zoom creates the spiral depth
    let sc = zoom * (1.0 + bass * 0.012);
    let r2 = radius / sc;

    // Back to cartesian for feedback sample
    p = vec2f(cos(angle) * r2, sin(angle) * r2);
    var fuv = p / vec2f(aspect, 1.0) + 0.5;

    // ═══════════════════════════════════════════════════════
    // FEEDBACK READ
    // ═══════════════════════════════════════════════════════

    var col = feedback(fuv).rgb;

    // Tiny spatial anti-aliasing blur on feedback
    let fb_blur = (
        feedback(fuv + vec2f( 0.001,  0.0)).rgb +
        feedback(fuv + vec2f(-0.001,  0.0)).rgb +
        feedback(fuv + vec2f( 0.0,  0.001)).rgb +
        feedback(fuv + vec2f( 0.0, -0.001)).rgb
    ) * 0.25;
    col = mix(col, fb_blur, 0.06);

    // Fade toward black
    let decay = 0.94 + loudness * 0.02;
    col *= decay;

    // Contrast enhancement — keeps edges crisp
    col = (col - 0.06) * 1.12;
    col = clamp(col, vec3f(0.0), vec3f(1.0));

    // ═══════════════════════════════════════════════════════
    // SPECTRAL LINES
    // ═══════════════════════════════════════════════════════
    // Thin radial lines driven by frequency bands. Louder bands
    // produce brighter, wider lines. The lines feed into the
    // kaleidoscope on subsequent frames, creating infinite regress.

    let bands = array<f32, 7>(sub, bass, low_mid, mid, up_mid, pres, brill);
    let hues  = array<f32, 7>(0.0, 0.08, 0.16, 0.35, 0.55, 0.68, 0.82);

    var lines = vec3f(0.0);
    let n = u32(line_count);

    for (var i = 0u; i < n; i++) {
        let fi = f32(i);
        let band_idx = i % 7u;
        let amp = bands[band_idx];
        if amp < 0.01 { continue; }

        // Line angle — evenly spaced + audio drift
        let base_angle = fi / line_count * 6.28318;
        let drift = sin(fi * 0.73 + t * (0.2 + amp * 0.4)) * amp * 0.03;
        let la = base_angle + drift;

        // Line endpoint — audio pushes it outward
        let lr = 0.05 + amp * 0.55 + onset * 0.08;

        // Pixel distance to this radial line
        let lx = uv.x - (0.5 + cos(la) * lr * 0.5);
        let ly = (uv.y - (0.5 + sin(la) * lr * 0.5 * aspect)) * aspect;
        let dist_to_line = abs(lx * sin(la) - ly * cos(la));

        // Gaussian line profile
        let w = line_width * (0.4 + amp * 1.6);
        let intensity = exp(-(dist_to_line * dist_to_line) / (w * w)) * amp * 0.55;

        if intensity < 0.001 { continue; }

        let h = fract(hues[band_idx] + centroid * 0.08);
        let line_col = hsv2rgb(vec3f(h, 0.65 + amp * 0.35, intensity));
        lines += line_col;
    }

    // ═══════════════════════════════════════════════════════
    // COMPOSITE
    // ═══════════════════════════════════════════════════════

    col += lines;

    // Beat: bright centre pulse
    let centre_dist = length(uv - 0.5);
    col += beat * exp(-centre_dist * 4.0) * 0.18;

    // Subtle vignette
    let vig = 1.0 - smoothstep(0.6, 1.5, centre_dist * 1.5) * 0.2;
    col *= vig;

    col = clamp(col, vec3f(0.0), vec3f(1.3));

    return vec4f(col, 1.0);
}
