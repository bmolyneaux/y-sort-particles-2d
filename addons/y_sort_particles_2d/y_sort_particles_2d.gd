@tool
class_name YSortParticles2D
extends Node2D
## A CPU particle emitter that drives one [Sprite2D] child per particle, so every
## particle participates in Y-sorting like a regular node.
##
## Behavior mirrors [GPUParticles2D] driven by a [ParticleProcessMaterial]: emission
## timing (explosiveness, randomness, preprocess), emission shapes, direction and
## spread, gravity, linear/radial/tangential acceleration, orbit velocity, damping,
## initial angle, angular velocity, scale/color/alpha over lifetime, and the
## align-Y particle flag.
##
## [member CanvasItem.y_sort_enabled] defaults to [code]true[/code] on this node so the
## particle sprites sort against each other; place the node under a Y-sorted parent for
## them to sort against the rest of the scene.
##
## Unsupported [ParticleProcessMaterial] features: turbulence, collision, attractors,
## sub-emitters, hue variation, sprite-sheet animation, point/directed-point emission
## shapes, per-axis scale curves ([CurveXYZTexture]), directional/radial velocity and
## velocity limits, and [GradientTexture2D] color ramps.

## Emitted when all particles are gone after emission stops (a [member one_shot] cycle
## completing, or [member emitting] being set to [code]false[/code]).
signal finished

## Flags for [method emit_particle]. Values match [enum GPUParticles2D.EmitFlags].
enum EmitFlags {
	EMIT_FLAG_POSITION = 1,
	EMIT_FLAG_ROTATION_SCALE = 2,
	EMIT_FLAG_VELOCITY = 4,
	EMIT_FLAG_COLOR = 8,
	EMIT_FLAG_CUSTOM = 16,
}

const _PREPROCESS_STEP := 1.0 / 30.0
const _MIN_SCALE := 0.0001
const _SPRITE_META := &"_ysort_particle"


class _Particle:
	var sprite: Sprite2D
	var active := false
	var time := 0.0
	var lifetime := 1.0
	## Randomizes this slot's restart time within the emission cycle. Re-rolled every
	## cycle so the jitter differs between cycles.
	var phase_jitter := 0.0
	## Position and velocity are in emitter-local space when local_coords is enabled,
	## global space otherwise.
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var rotation := 0.0
	var base_angle := 0.0  # Degrees.
	var angular_velocity := 0.0  # Degrees per second.
	var base_scale := 1.0
	var base_color := Color.WHITE
	var linear_accel := 0.0
	var radial_accel := 0.0
	var tangential_accel := 0.0
	var damping := 0.0
	var orbit_velocity := 0.0  # Revolutions per second.
	var draw_scale := 1.0
	var draw_color := Color.WHITE


## If [code]true[/code], particles are being emitted. Setting it to [code]true[/code]
## again after a [member one_shot] cycle has finished starts a new cycle.
@export var emitting := false:
	set(value):
		if emitting == value:
			return
		emitting = value
		if emitting and is_inside_tree():
			if not _active or (one_shot and _time >= lifetime):
				_start_cycle()
			# Otherwise emission resumes within the already-running cycle.

## Number of particles in the system. Each particle is a [Sprite2D] child, so keep this
## far lower than you would for [GPUParticles2D]. The sprites are created lazily when
## emission first starts, so a node that never emits allocates none.
@export_range(1, 1000, 1, "or_greater") var amount := 8:
	set(value):
		amount = maxi(1, value)
		if not _particles.is_empty():
			_sync_pool()

@export_group("Time")
## Amount of time each particle will exist, in seconds.
@export_range(0.01, 600.0, 0.01, "or_greater", "suffix:s") var lifetime := 1.0
## If [code]true[/code], only one emission cycle occurs.
@export var one_shot := false
## Amount of time to simulate before the first frame is drawn, so the system starts
## already filled with particles.
@export_range(0.0, 600.0, 0.01, "or_greater", "suffix:s") var preprocess := 0.0
## Speed multiplier for the particle simulation. [code]0[/code] pauses it.
@export_range(0.0, 64.0, 0.01) var speed_scale := 1.0
## How quickly particles are emitted within a cycle. [code]0[/code] spreads them evenly
## over the lifetime, [code]1[/code] emits them all at once.
@export_range(0.0, 1.0, 0.01) var explosiveness := 0.0
## Randomness of each particle's emission time within the cycle. Lifetime randomness is
## controlled by [member ParticleProcessMaterial.lifetime_randomness] instead.
@export_range(0.0, 1.0, 0.01) var randomness := 0.0

@export_group("Drawing")
## If [code]true[/code], particles follow this node's transform. If [code]false[/code],
## they simulate in global space and are unaffected by the emitter moving.
@export var local_coords := false
## The texture drawn for each particle.
@export var texture: Texture2D:
	set(value):
		texture = value
		for particle in _particles:
			if is_instance_valid(particle.sprite):
				particle.sprite.texture = texture
		update_configuration_warnings()

@export_group("Process Material")
## [ParticleProcessMaterial] that defines particle behavior. If unassigned, the defaults
## of a fresh material are used.
@export var process_material: ParticleProcessMaterial:
	set(value):
		process_material = value
		update_configuration_warnings()


var _particles: Array[_Particle] = []
var _time := 0.0
var _active := false
var _rng := RandomNumberGenerator.new()
var _fallback_material: ParticleProcessMaterial


func _init() -> void:
	_rng.randomize()
	y_sort_enabled = true


func _ready() -> void:
	_clear_stale_sprites()
	if emitting:
		_start_cycle()


func _process(delta: float) -> void:
	if not _active:
		return
	_simulate(delta * speed_scale)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if process_material == null:
		warnings.append("A ParticleProcessMaterial is not assigned, so particles will use default behavior.")
	if texture == null:
		warnings.append("A texture is not assigned, so particles will be invisible.")
	return warnings


#region Public API

## Restarts the emission cycle, removing all existing particles first.
func restart() -> void:
	for particle in _particles:
		_deactivate(particle)
	_active = false
	if emitting:
		_start_cycle()
	else:
		emitting = true  # The setter starts the cycle.


## Emits one particle, mimicking [method GPUParticles2D.emit_particle]. Properties not
## covered by [param flags] are randomized from the process material as usual.
## [param xform] is in the same space the particles simulate in (global coordinates
## unless [member local_coords] is enabled). [param custom] is accepted for API
## compatibility but unused. Does nothing if all particle slots are currently active.
func emit_particle(xform: Transform2D, velocity: Vector2, color: Color, _custom: Color, flags: int) -> void:
	if not is_inside_tree():
		return
	_sync_pool()
	var slot: _Particle = null
	for particle in _particles:
		if not particle.active:
			slot = particle
			break
	if slot == null:
		return

	var material := _material()
	var emit_xform := Transform2D.IDENTITY if local_coords else global_transform
	_init_particle(slot, material, emit_xform)
	if flags & EmitFlags.EMIT_FLAG_POSITION:
		slot.position = xform.origin
	if flags & EmitFlags.EMIT_FLAG_ROTATION_SCALE:
		slot.base_angle = rad_to_deg(xform.get_rotation())
		slot.rotation = xform.get_rotation()
		slot.base_scale = xform.get_scale().x
	if flags & EmitFlags.EMIT_FLAG_VELOCITY:
		slot.velocity = velocity
	if flags & EmitFlags.EMIT_FLAG_COLOR:
		slot.base_color = color

	_active = true
	# Present the particle at its spawn state immediately instead of waiting a frame.
	_step_particle(slot, material, 0.0, emit_xform.origin, Vector2.ZERO)
	_draw_particle(slot, Transform2D.IDENTITY if local_coords else global_transform.affine_inverse())


## Returns the bounding rectangle of all active particles (including their texture
## extents) in this node's local coordinate space.
func capture_rect() -> Rect2:
	var to_node := Transform2D.IDENTITY
	if not local_coords and is_inside_tree():
		to_node = global_transform.affine_inverse()
	var half_extents := texture.get_size() * 0.5 if texture else Vector2.ZERO

	var rect := Rect2()
	var first := true
	for particle in _particles:
		if not particle.active:
			continue
		var extents := half_extents * absf(particle.draw_scale)
		var particle_rect := Rect2(to_node * particle.position - extents, extents * 2.0)
		rect = particle_rect if first else rect.merge(particle_rect)
		first = false
	return rect

#endregion


#region Sprite pool

func _sync_pool() -> void:
	while _particles.size() > amount:
		var particle: _Particle = _particles.pop_back()
		if is_instance_valid(particle.sprite):
			particle.sprite.queue_free()
	while _particles.size() < amount:
		var particle := _Particle.new()
		particle.phase_jitter = _rng.randf()
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.visible = false
		sprite.set_meta(_SPRITE_META, true)
		add_child(sprite, false, Node.INTERNAL_MODE_BACK)
		particle.sprite = sprite
		_particles.append(particle)


## Frees particle sprites left over from Node.duplicate() or similar, which are not in
## the pool and would otherwise linger as orphaned children.
func _clear_stale_sprites() -> void:
	var pooled := {}
	for particle in _particles:
		pooled[particle.sprite] = true
	for child in get_children(true):
		if child is Sprite2D and child.has_meta(_SPRITE_META) and not pooled.has(child):
			child.queue_free()

#endregion


#region Simulation

func _start_cycle() -> void:
	_sync_pool()
	_time = 0.0
	_active = true
	if preprocess > 0.0 and is_inside_tree():
		var remaining := preprocess
		while remaining > 0.0:
			var step := minf(_PREPROCESS_STEP, remaining)
			_simulate(step)
			remaining -= step


func _simulate(delta: float) -> void:
	if delta <= 0.0 or _particles.is_empty() or not is_inside_tree():
		return

	var material := _material()
	var life := maxf(lifetime, 0.0001)
	var count := _particles.size()
	var emit_xform := Transform2D.IDENTITY if local_coords else global_transform
	var sim_to_node := Transform2D.IDENTITY if local_coords else global_transform.affine_inverse()
	var gravity := Vector2(material.gravity.x, material.gravity.y)

	var prev_phase := _time / life
	_time += delta
	var wrapped := false
	if _time > life:
		if one_shot:
			_time = life
			emitting = false
		else:
			_time = fmod(_time, life)
			wrapped = true
	var phase := _time / life

	var active_count := 0
	for i in count:
		var particle := _particles[i]

		# Each slot restarts once per cycle at its own phase, spread across the cycle
		# and compressed toward 0 by explosiveness, like GPUParticles2D.
		var restart_phase := (float(i) + randomness * particle.phase_jitter) \
				/ float(count) * (1.0 - explosiveness)
		var restart: bool
		if wrapped:
			restart = restart_phase >= prev_phase or restart_phase < phase
		else:
			restart = restart_phase >= prev_phase and restart_phase < phase

		var particle_delta := delta
		if restart:
			particle.phase_jitter = _rng.randf()
			if emitting:
				_init_particle(particle, material, emit_xform)
				# Advance the new particle by the time elapsed since its scheduled
				# restart within this frame, keeping emission framerate-independent.
				if restart_phase <= phase:
					particle_delta = (phase - restart_phase) * life
				else:
					particle_delta = (1.0 - restart_phase + phase) * life
			elif particle.active:
				_deactivate(particle)

		if not particle.active:
			continue
		_step_particle(particle, material, particle_delta, emit_xform.origin, gravity)
		if particle.active:
			active_count += 1
			_draw_particle(particle, sim_to_node)

	if _active and active_count == 0 and not emitting:
		_active = false
		finished.emit()


func _init_particle(particle: _Particle, material: ParticleProcessMaterial, emit_xform: Transform2D) -> void:
	particle.active = true
	particle.time = 0.0
	particle.lifetime = maxf(lifetime * (1.0 - material.lifetime_randomness * _rng.randf()), 0.001)

	particle.base_angle = _rng.randf_range(material.angle_min, material.angle_max)
	particle.rotation = deg_to_rad(particle.base_angle)
	particle.angular_velocity = _rng.randf_range(material.angular_velocity_min, material.angular_velocity_max)
	particle.base_scale = _rng.randf_range(material.scale_min, material.scale_max)
	particle.linear_accel = _rng.randf_range(material.linear_accel_min, material.linear_accel_max)
	particle.radial_accel = _rng.randf_range(material.radial_accel_min, material.radial_accel_max)
	particle.tangential_accel = _rng.randf_range(material.tangential_accel_min, material.tangential_accel_max)
	particle.damping = _rng.randf_range(material.damping_min, material.damping_max)
	particle.orbit_velocity = _rng.randf_range(material.orbit_velocity_min, material.orbit_velocity_max)

	particle.base_color = material.color
	var initial_ramp := _gradient_of(material.color_initial_ramp)
	if initial_ramp:
		particle.base_color = particle.base_color * initial_ramp.sample(_rng.randf())

	var direction_angle := atan2(material.direction.y, material.direction.x) \
			+ deg_to_rad(material.spread) * (_rng.randf() * 2.0 - 1.0)
	particle.velocity = Vector2.from_angle(direction_angle) \
			* _rng.randf_range(material.initial_velocity_min, material.initial_velocity_max)

	var spawn := _emission_point(material)
	spawn = spawn * Vector2(material.emission_shape_scale.x, material.emission_shape_scale.y) \
			+ Vector2(material.emission_shape_offset.x, material.emission_shape_offset.y)

	particle.position = emit_xform * spawn
	particle.velocity = emit_xform.basis_xform(particle.velocity)


func _emission_point(material: ParticleProcessMaterial) -> Vector2:
	match material.emission_shape:
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
			# Uniform over the disk area, the 2D equivalent of a filled sphere.
			var radius := material.emission_sphere_radius * sqrt(_rng.randf())
			return Vector2.from_angle(_rng.randf() * TAU) * radius
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			return Vector2.from_angle(_rng.randf() * TAU) * material.emission_sphere_radius
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			return Vector2(
				_rng.randf_range(-material.emission_box_extents.x, material.emission_box_extents.x),
				_rng.randf_range(-material.emission_box_extents.y, material.emission_box_extents.y),
			)
		ParticleProcessMaterial.EMISSION_SHAPE_RING:
			# The ring axis is ignored; the ring always lies in the 2D plane.
			var inner := material.emission_ring_inner_radius
			var outer := material.emission_ring_radius
			var radius := sqrt(_rng.randf_range(inner * inner, outer * outer))
			return Vector2.from_angle(_rng.randf() * TAU) * radius
		_:
			# EMISSION_SHAPE_POINT; the points/directed-points shapes are unsupported.
			return Vector2.ZERO


func _step_particle(particle: _Particle, material: ParticleProcessMaterial, delta: float, emit_origin: Vector2, gravity: Vector2) -> void:
	particle.time += delta
	if particle.time >= particle.lifetime:
		_deactivate(particle)
		return
	var phase := particle.time / particle.lifetime
	var offset := particle.position - emit_origin

	var force := gravity
	if particle.linear_accel != 0.0 and particle.velocity != Vector2.ZERO:
		force += particle.velocity.normalized() \
				* (particle.linear_accel * _sample_curve(material.linear_accel_curve, phase))
	if offset != Vector2.ZERO:
		if particle.radial_accel != 0.0:
			force += offset.normalized() \
					* (particle.radial_accel * _sample_curve(material.radial_accel_curve, phase))
		if particle.tangential_accel != 0.0:
			force += Vector2(-offset.y, offset.x).normalized() \
					* (particle.tangential_accel * _sample_curve(material.tangential_accel_curve, phase))
	particle.velocity += force * delta

	# Orbit velocity rotates the particle around the emitter origin, in revolutions
	# per second.
	if particle.orbit_velocity != 0.0 and offset != Vector2.ZERO:
		var turn := particle.orbit_velocity * _sample_curve(material.orbit_velocity_curve, phase) * TAU * delta
		particle.position = emit_origin + offset.rotated(turn)

	# Damping removes a fixed amount of speed per second rather than a ratio.
	if particle.damping > 0.0 and particle.velocity != Vector2.ZERO:
		var speed := particle.velocity.length() \
				- particle.damping * _sample_curve(material.damping_curve, phase) * delta
		particle.velocity = particle.velocity.normalized() * maxf(speed, 0.0)

	particle.position += particle.velocity * delta

	# Rotation is not integrated: it is the base angle plus age * velocity * curve,
	# matching the ParticleProcessMaterial shader.
	var angle := particle.base_angle + particle.time * particle.angular_velocity \
			* _sample_curve(material.angular_velocity_curve, phase)
	particle.rotation = deg_to_rad(angle)
	if material.particle_flag_align_y and particle.velocity != Vector2.ZERO:
		particle.rotation = atan2(-particle.velocity.x, particle.velocity.y)

	particle.draw_scale = particle.base_scale * _sample_curve(material.scale_curve, phase)
	if absf(particle.draw_scale) < _MIN_SCALE:
		particle.draw_scale = _MIN_SCALE

	var color := particle.base_color
	var ramp := _gradient_of(material.color_ramp)
	if ramp:
		color *= ramp.sample(phase)
	color.a *= _sample_curve(material.alpha_curve, phase)
	particle.draw_color = color


func _draw_particle(particle: _Particle, sim_to_node: Transform2D) -> void:
	var scale_2d := Vector2(particle.draw_scale, particle.draw_scale)
	particle.sprite.transform = sim_to_node \
			* Transform2D(particle.rotation, scale_2d, 0.0, particle.position)
	particle.sprite.modulate = particle.draw_color
	particle.sprite.visible = true


func _deactivate(particle: _Particle) -> void:
	particle.active = false
	if is_instance_valid(particle.sprite):
		particle.sprite.visible = false

#endregion


#region Helpers

func _material() -> ParticleProcessMaterial:
	if process_material:
		return process_material
	if _fallback_material == null:
		_fallback_material = ParticleProcessMaterial.new()
	return _fallback_material


static func _sample_curve(curve_texture: Texture2D, phase: float) -> float:
	var typed := curve_texture as CurveTexture
	if typed and typed.curve:
		return typed.curve.sample_baked(phase)
	return 1.0


static func _gradient_of(ramp: Texture2D) -> Gradient:
	var typed := ramp as GradientTexture1D
	return typed.gradient if typed else null

#endregion
