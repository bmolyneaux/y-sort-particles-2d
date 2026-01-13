# SortedParticles2D TODO

## Code Cleanup

- [x] Remove unused `fract_delta` property (exported but never used)
- [x] Remove unused `visibility_rect` property (exported but never used for culling)

## Export Hints

Add `##` doc comments above each `@export` for inspector tooltips:

- [x] `emitting` - "If true, particles are being emitted."
- [x] `amount` - "Number of particles emitted per cycle."
- [x] `one_shot` - "If true, emits particles once then stops."
- [x] `lifetime` - "Amount of time each particle will exist (in seconds)."
- [x] `speed_scale` - "Speed multiplier for the particle simulation."
- [x] `explosiveness` - "Fraction of the lifetime over which to emit. 0 = spread evenly, 1 = all at once."
- [x] `randomness` - "Randomness ratio applied to each particle's lifetime."
- [x] `local_coords` - "If true, particles are emitted relative to the node. If false, they use global coordinates."
- [x] `texture` - "The texture used for each particle sprite."
- [x] `process_material` - "ParticleProcessMaterial that defines particle behavior."

## Missing ParticleProcessMaterial Features

### High Priority
- [x] `radial_accel_min` / `radial_accel_max` / `radial_accel_curve` - Acceleration away from emission origin
- [ ] `tangential_accel_min` / `tangential_accel_max` - Acceleration perpendicular to velocity
- [ ] `linear_accel_min` / `linear_accel_max` - Constant acceleration in initial direction
- [ ] `emission_ring_axis` / `emission_ring_height` / `emission_ring_radius` / `emission_ring_inner_radius` - Ring emission shape

### Medium Priority
- [ ] `orbit_velocity_min` / `orbit_velocity_max` / `orbit_velocity_curve` - Circular motion around origin
- [ ] `angle_min` / `angle_max` / `angle_curve` - Initial rotation angle
- [ ] `color_initial_ramp` - Randomize initial particle color from gradient
- [ ] `emission_curve` - Control emission timing with a curve
- [ ] `velocity_pivot` - Pivot point for velocity calculations

### Low Priority
- [ ] `directional_velocity_min` / `directional_velocity_max` / `directional_velocity_curve` - Velocity in initial direction over lifetime
- [ ] `radial_velocity_min` / `radial_velocity_max` / `radial_velocity_curve` - Radial velocity over lifetime
- [ ] `scale_over_velocity_min` / `scale_over_velocity_max` / `scale_over_velocity_curve` - Scale based on velocity
- [ ] `inherit_velocity_ratio` - Inherit emitter velocity
- [ ] `turbulence_enabled` / `turbulence_*` - Noise-based movement

### Not Planned
- Sub-emitters (requires node spawning architecture)
- Trails (requires different rendering approach)
- Collision (requires physics integration)
- Attractor interaction (requires separate node type)
