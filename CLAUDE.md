# Phosphor Shader Authoring Rules

## Entry Point

Every effect shader MUST use this exact entry point:

```wgsl
@fragment
fn fs_main(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
    let res = u.resolution;
    let uv = frag_coord.xy / res;
    // ...
    return vec4f(colour, 1.0);
}
```

Do NOT use `fn effect(uv)` — that's an outdated API. Built-in uniforms are accessed
via `u.` prefix (e.g. `u.time`, `u.bass`, `u.rms`).

## Available Uniforms

All accessed as `u.<name>`:

**Core:** `time` (f32), `resolution` (vec2f), `frame_index` (f32)

**Audio bands (0-1):** `sub_bass`, `bass`, `low_mid`, `mid`, `upper_mid`, `presence`, `brilliance`

**Audio aggregates (0-1):** `rms` (loudness), `kick`, `onset`, `centroid` (spectral brightness),
`flux` (rate of change), `flatness` (noise vs tone), `rolloff`, `bandwidth`, `zcr`

**Beat detection:** `beat` (0/1, 1.0 on beat frame), `beat_phase` (0-1 sawtooth at BPM),
`beat_strength` (confidence), `bpm` (BPM/300)

**Advanced:** `mfcc(i: u32) → f32` (13 MFCCs, i=0..12), `chroma_val(i: u32) → f32` (12 pitch classes)

## Parameters

Define in `.pfx` `inputs` array. Access in shader via `param(0u)` through `param(15u)`.
Up to 16 float params. Map 0-1 range as needed in shader.

## Feedback

Enable per-pass with `"feedback": true` in `.pfx`. Read previous frame via `feedback(uv) → vec4f`.

## Built-in Library

Auto-prepended. Available functions:
- `hash(p: vec2f) → f32` — deterministic pseudo-random
- `noise2d(p: vec2f) → f32`, `fbm2d(p: vec2f) → f32`
- `palette(t, a, b, c, d: f32) → vec3f` — cosine colour palette
- `sd_circle`, `sd_box`, `sd_line`, `sd_ring` — SDF primitives
- `phosphor_audio_palette(t, centroid, beat_phase: f32) → vec3f` — audio-driven palette
- `aces_tonemap(col: vec3f) → vec3f`, `gamma`, `linear_to_srgb`

## .pfx File Format

```json
{
    "name": "Effect Name",
    "author": "You",
    "description": "What it does",
    "shader": "",
    "passes": [
        {
            "name": "main",
            "shader": "effect_name.wgsl",
            "feedback": true
        }
    ],
    "inputs": [
        { "type": "Float", "name": "param_name", "default": 0.5, "min": 0.0, "max": 1.0 }
    ],
    "postprocess": {
        "enabled": true,
        "bloom_threshold": 0.4,
        "bloom_intensity": 0.6,
        "vignette": 0.3
    }
}
```

## File Locations

- Custom effects: `effects/*.pfx` + `effects/*.wgsl` (versioned in project repo)
- At runtime, shellHook copies them to `assets/effects/` and `assets/shaders/`
- Phosphor scans `assets/effects/` for .pfx files on launch
- Shader hot-reloads on save — edit `.wgsl`, see change instantly

## Common Pitfalls

1. **Wrong entry point**: must be `@fragment fn fs_main(@builtin(position) frag_coord: vec4f)`
   NOT `fn effect(uv: vec2f)`
2. **Missing `@location(0)` return attribute**: required
3. **Uniform access**: `u.bass` not `bass`, `u.rms` not `rms`
4. **Parameters**: `param(0u)` with `u` suffix (u32 literal)
5. **Feedback**: must be enabled in .pfx pass definition, accessed via `feedback(uv)`
6. **Alpha channel**: must return `vec4f` with alpha, not `vec3f`
7. **Shader in wrong dir**: `.wgsl` files go in `assets/shaders/` (resolved by Phosphor),
   not in `assets/effects/`
