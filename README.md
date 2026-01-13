# YSortParticles2D

A Godot 4 addon that provides a particle system compatible with Y-sorting. Unlike `GPUParticles2D`, each particle is spawned as a `Sprite2D` child node, allowing particles to properly sort with other 2D elements based on their Y position.

## Why?

Godot's built-in `GPUParticles2D` renders all particles as a single draw call on the GPU, which means particles cannot participate in Y-sorting with other nodes. This addon solves that by simulating particles on the CPU and spawning each as an individual `Sprite2D`.

**Trade-off:** Lower performance than GPU particles, but proper Y-sort integration.

## Installation

1. Copy the `addons/y_sort_particles_2d` folder into your project's `addons/` directory
2. Enable the plugin in **Project → Project Settings → Plugins**
3. Add a `YSortParticles2D` node to your scene

## Usage

`YSortParticles2D` uses the same `ParticleProcessMaterial` as `GPUParticles2D`, so you can configure particle behavior the same way:

```gdscript
var particles = $YSortParticles2D
particles.texture = preload("res://particle.png")
particles.process_material = ParticleProcessMaterial.new()
particles.process_material.gravity = Vector3(0, 980, 0)
particles.process_material.initial_velocity_min = 100
particles.process_material.initial_velocity_max = 200
particles.emitting = true
```

For Y-sorting to work, ensure the parent node has `y_sort_enabled = true`.

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `emitting` | bool | false | Whether particles are being emitted |
| `amount` | int | 8 | Number of particles per emission cycle |
| `one_shot` | bool | false | If true, emits once then stops |
| `lifetime` | float | 1.0 | How long each particle lives (seconds) |
| `speed_scale` | float | 1.0 | Simulation speed multiplier |
| `explosiveness` | float | 0.0 | Fraction of lifetime over which to emit (0=spread, 1=instant) |
| `randomness` | float | 0.0 | Randomness applied to particle lifetime |
| `local_coords` | bool | false | Emit in local vs global coordinates |
| `texture` | Texture2D | null | Sprite texture for particles |
| `process_material` | ParticleProcessMaterial | null | Material defining particle behavior |

## Signals

| Signal | Description |
|--------|-------------|
| `finished` | Emitted when `one_shot` completes and all particles have died |

## Methods

| Method | Description |
|--------|-------------|
| `restart()` | Clears all particles and restarts emission |
| `emit_particle(xform, velocity, color, custom, flags)` | Manually emit a single particle |
| `capture_rect() -> Rect2` | Returns bounding box of all active particles |

## Supported ParticleProcessMaterial Properties

The following properties are read from the assigned `ParticleProcessMaterial`:

- **Emission:** `emission_shape`, `emission_sphere_radius`, `emission_box_extents`
- **Direction:** `direction`, `spread`
- **Velocity:** `initial_velocity_min`, `initial_velocity_max`
- **Angular:** `angular_velocity_min`, `angular_velocity_max`
- **Physics:** `gravity`, `damping_min`, `damping_max`, `radial_accel_min`, `radial_accel_max`, `radial_accel_curve`
- **Scale:** `scale_min`, `scale_max`, `scale_curve`
- **Color:** `color`, `color_ramp`, `alpha_curve`

## Not Implemented

The following `GPUParticles2D` features are intentionally omitted:

- Sub-emitters (`sub_emitter_mode`)
- Trails (`trail_enabled`, `trail_lifetime`, etc.)
- Preprocess
- Interpolation
- Fixed FPS
- Draw order enum
- Collision
- `request_particles_process()`
- `amount_ratio`
- Hue variation (`hue_variation_min`, `hue_variation_max`, `hue_variation_curve`)

## License

MIT
