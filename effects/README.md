# Custom Effects

Drop `.pfx` + `.wgsl` files into `~/.config/phosphor/effects/`.
Phosphor picks them up automatically — they appear in the Effects panel.

To hot-reload while editing:
- Edit the `.wgsl` file in `~/.config/phosphor/effects/`
- Save → Phosphor recompiles instantly (with error recovery)

## Included effects

### Glow Particles
White glowing particles with slow circular drift. Louder audio → faster motion,
more colour saturation. Bass shifts hue warm, highs shift it cool. Beat triggers
a quick outward burst. Feedback trails.

Params:
- `particle_count` — 20–160 particles
- `glow_size` — glow radius
- `base_speed` — orbit speed
- `audio_drive` — how strongly audio affects motion
- `trail_decay` — how fast feedback trails fade
