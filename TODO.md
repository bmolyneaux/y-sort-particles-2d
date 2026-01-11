# SortedParticles2D TODO

## Code Cleanup

- [ ] Remove unused `fract_delta` property (exported but never used)
- [ ] Remove unused `visibility_rect` property (exported but never used for culling)

## Export Hints

Add `##` doc comments above each `@export` for inspector tooltips:

- [ ] `emitting` - "If true, particles are being emitted."
- [ ] `amount` - "Number of particles emitted per cycle."
- [ ] `one_shot` - "If true, emits particles once then stops."
- [ ] `lifetime` - "Amount of time each particle will exist (in seconds)."
- [ ] `speed_scale` - "Speed multiplier for the particle simulation."
- [ ] `explosiveness` - "Fraction of the lifetime over which to emit. 0 = spread evenly, 1 = all at once."
- [ ] `randomness` - "Randomness ratio applied to each particle's lifetime."
- [ ] `local_coords` - "If true, particles are emitted relative to the node. If false, they use global coordinates."
- [ ] `texture` - "The texture used for each particle sprite."
- [ ] `process_material` - "ParticleProcessMaterial that defines particle behavior."

## Missing ParticleProcessMaterial Features

### High Priority
- [ ] `radial_accel_min` / `radial_accel_max` - Acceleration away from emission origin
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
