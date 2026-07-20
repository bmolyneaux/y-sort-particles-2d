@tool
class_name YSortParticles2D
extends Node2D
## A CPU particle emitter that drives one [Sprite2D] child per particle, so every
## particle participates in Y-sorting like a regular node.
##
## Behavior mirrors [GPUParticles2D] driven by a [ParticleProcessMaterial]: emission
## timing (explosiveness, randomness, preprocess), emission shapes (including point
## textures), direction and spread, gravity, linear/radial/tangential acceleration,
## orbit velocity, damping, initial angle, angular velocity, hue variation,
## scale/color/alpha over lifetime, the align-Y particle flag, and sub-emitters.
##
## Sprite-sheet animation is configured the same way as [GPUParticles2D]: assign a
## [CanvasItemMaterial] with [member CanvasItemMaterial.particles_animation] enabled to
## [member CanvasItem.material], and the h/v frame counts and looping are read from it.
##
## [member CanvasItem.y_sort_enabled] defaults to [code]true[/code] on this node so the
## particle sprites sort against each other; place the node under a Y-sorted parent for
## them to sort against the rest of the scene.
##
## Unsupported [ParticleProcessMaterial] features (also unsupported by
## [CPUParticles2D]): turbulence, collision (including at-collision sub-emission),
## attractors, and the newer directional/radial velocity, velocity limit, velocity
## pivot, and scale-over-velocity properties. [GradientTexture2D] ramps use only their
## gradient; the fill pattern is ignored.

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
## Limits sub-emitter chains, including accidental cycles.
const _MAX_SUB_EMISSION_DEPTH := 8

static var _sub_emission_depth := 0


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
	var hue_rot := 0.0  # Fraction of a full hue rotation.
	var linear_accel := 0.0
	var radial_accel := 0.0
	var tangential_accel := 0.0
	var damping := 0.0
	var orbit_velocity := 0.0  # Revolutions per second.
	var anim_offset := 0.0
	var anim_speed := 0.0
	var anim_pos := 0.0
	var draw_scale := Vector2.ONE
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

## Path to another [YSortParticles2D] used as a sub-emitter. Enable it by setting
## [member ParticleProcessMaterial.sub_emitter_mode]; the constant, at-start, and
## at-end modes are supported.
@export_node_path var sub_emitter: NodePath:
	set(value):
		sub_emitter = value
		update_configuration_warnings()

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
		_image_cache.clear()
		update_configuration_warnings()


var _particles: Array[_Particle] = []
var _time := 0.0
var _active := false
var _rng := RandomNumberGenerator.new()
var _fallback_material: ParticleProcessMaterial
## Caches decompressed images of the emission point/normal/color textures.
var _image_cache := {}
var _anim_h_frames := 1
var _anim_v_frames := 1
var _anim_loop := false


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
	if not sub_emitter.is_empty() and _resolve_sub_emitter() == null:
		warnings.append("The sub_emitter path must point to a different YSortParticles2D node.")
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

	var mat := _material()
	var emit_xform := Transform2D.IDENTITY if local_coords else global_transform
	_init_particle(slot, mat, emit_xform, _resolve_sub_emitter())
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
	_refresh_anim_config()
	_step_particle(slot, mat, 0.0, emit_xform.origin, Vector2.ZERO, null)
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
		var extents := half_extents * particle.draw_scale.abs()
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

	var mat := _material()
	var life := maxf(lifetime, 0.0001)
	var count := _particles.size()
	var emit_xform := Transform2D.IDENTITY if local_coords else global_transform
	var sim_to_node := Transform2D.IDENTITY if local_coords else global_transform.affine_inverse()
	var gravity := Vector2(mat.gravity.x, mat.gravity.y)
	var sub := _resolve_sub_emitter()
	_refresh_anim_config()

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
				_init_particle(particle, mat, emit_xform, sub)
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
		_step_particle(particle, mat, particle_delta, emit_xform.origin, gravity, sub)
		if particle.active:
			active_count += 1
			_draw_particle(particle, sim_to_node)

	if _active and active_count == 0 and not emitting:
		_active = false
		finished.emit()


func _init_particle(particle: _Particle, mat: ParticleProcessMaterial, emit_xform: Transform2D, sub: YSortParticles2D) -> void:
	particle.active = true
	particle.time = 0.0
	particle.lifetime = maxf(lifetime * (1.0 - mat.lifetime_randomness * _rng.randf()), 0.001)

	particle.base_angle = _rng.randf_range(mat.angle_min, mat.angle_max)
	particle.rotation = deg_to_rad(particle.base_angle)
	particle.angular_velocity = _rng.randf_range(mat.angular_velocity_min, mat.angular_velocity_max)
	particle.base_scale = _rng.randf_range(mat.scale_min, mat.scale_max)
	particle.hue_rot = _rng.randf_range(mat.hue_variation_min, mat.hue_variation_max)
	particle.linear_accel = _rng.randf_range(mat.linear_accel_min, mat.linear_accel_max)
	particle.radial_accel = _rng.randf_range(mat.radial_accel_min, mat.radial_accel_max)
	particle.tangential_accel = _rng.randf_range(mat.tangential_accel_min, mat.tangential_accel_max)
	particle.damping = _rng.randf_range(mat.damping_min, mat.damping_max)
	particle.orbit_velocity = _rng.randf_range(mat.orbit_velocity_min, mat.orbit_velocity_max)
	particle.anim_offset = _rng.randf_range(mat.anim_offset_min, mat.anim_offset_max)
	particle.anim_speed = _rng.randf_range(mat.anim_speed_min, mat.anim_speed_max)
	particle.anim_pos = particle.anim_offset

	particle.base_color = mat.color
	var initial_ramp := _gradient_of(mat.color_initial_ramp)
	if initial_ramp:
		particle.base_color = particle.base_color * initial_ramp.sample(_rng.randf())

	var direction_angle := atan2(mat.direction.y, mat.direction.x) \
			+ deg_to_rad(mat.spread) * (_rng.randf() * 2.0 - 1.0)
	particle.velocity = Vector2.from_angle(direction_angle) \
			* _rng.randf_range(mat.initial_velocity_min, mat.initial_velocity_max)

	var spawn: Vector2
	if mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_POINTS \
			or mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS:
		spawn = _emission_from_points(particle, mat)
	else:
		spawn = _emission_point(mat)
	spawn = spawn * Vector2(mat.emission_shape_scale.x, mat.emission_shape_scale.y) \
			+ Vector2(mat.emission_shape_offset.x, mat.emission_shape_offset.y)

	particle.position = emit_xform * spawn
	particle.velocity = emit_xform.basis_xform(particle.velocity)

	if sub and mat.sub_emitter_mode == ParticleProcessMaterial.SUB_EMITTER_AT_START:
		_trigger_sub_emission(sub, mat, particle, mat.sub_emitter_amount_at_start)


func _emission_point(mat: ParticleProcessMaterial) -> Vector2:
	match mat.emission_shape:
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
			# Uniform over the disk area, the 2D equivalent of a filled sphere.
			var radius := mat.emission_sphere_radius * sqrt(_rng.randf())
			return Vector2.from_angle(_rng.randf() * TAU) * radius
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			return Vector2.from_angle(_rng.randf() * TAU) * mat.emission_sphere_radius
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			return Vector2(
				_rng.randf_range(-mat.emission_box_extents.x, mat.emission_box_extents.x),
				_rng.randf_range(-mat.emission_box_extents.y, mat.emission_box_extents.y),
			)
		ParticleProcessMaterial.EMISSION_SHAPE_RING:
			# The ring axis is ignored; the ring always lies in the 2D plane.
			var inner := mat.emission_ring_inner_radius
			var outer := mat.emission_ring_radius
			var radius := sqrt(_rng.randf_range(inner * inner, outer * outer))
			return Vector2.from_angle(_rng.randf() * TAU) * radius
		_:
			return Vector2.ZERO


## Samples a spawn point from the emission point texture. For directed points the
## normal texture reorients the initial velocity, and the color texture (if any) tints
## the particle, matching the GPU behavior of these emission shapes.
func _emission_from_points(particle: _Particle, mat: ParticleProcessMaterial) -> Vector2:
	var points := _cached_image(mat.emission_point_texture)
	if points == null:
		return Vector2.ZERO
	var point_count := mini(mat.emission_point_count, points.get_width() * points.get_height())
	if point_count <= 0:
		return Vector2.ZERO
	var index := _rng.randi() % point_count

	if mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS:
		var normals := _cached_image(mat.emission_normal_texture)
		if normals and index < normals.get_width() * normals.get_height():
			var normal_pixel := _image_pixel(normals, index)
			var normal := Vector2(normal_pixel.r, normal_pixel.g)
			if normal != Vector2.ZERO:
				normal = normal.normalized()
				var v := particle.velocity
				particle.velocity = Vector2(
					v.x * normal.x - v.y * normal.y,
					v.x * normal.y + v.y * normal.x,
				)

	var colors := _cached_image(mat.emission_color_texture)
	if colors and index < colors.get_width() * colors.get_height():
		particle.base_color = particle.base_color * _image_pixel(colors, index)

	var point := _image_pixel(points, index)
	return Vector2(point.r, point.g)


func _step_particle(particle: _Particle, mat: ParticleProcessMaterial, delta: float, emit_origin: Vector2, gravity: Vector2, sub: YSortParticles2D) -> void:
	var prev_time := particle.time
	particle.time += delta
	if particle.time >= particle.lifetime:
		if sub and mat.sub_emitter_mode == ParticleProcessMaterial.SUB_EMITTER_AT_END:
			_trigger_sub_emission(sub, mat, particle, mat.sub_emitter_amount_at_end)
		_deactivate(particle)
		return
	var phase := particle.time / particle.lifetime
	var offset := particle.position - emit_origin

	var force := gravity
	if particle.linear_accel != 0.0 and particle.velocity != Vector2.ZERO:
		force += particle.velocity.normalized() \
				* (particle.linear_accel * _sample_curve(mat.linear_accel_curve, phase))
	if offset != Vector2.ZERO:
		if particle.radial_accel != 0.0:
			force += offset.normalized() \
					* (particle.radial_accel * _sample_curve(mat.radial_accel_curve, phase))
		if particle.tangential_accel != 0.0:
			force += Vector2(-offset.y, offset.x).normalized() \
					* (particle.tangential_accel * _sample_curve(mat.tangential_accel_curve, phase))
	particle.velocity += force * delta

	# Orbit velocity rotates the particle around the emitter origin, in revolutions
	# per second.
	if particle.orbit_velocity != 0.0 and offset != Vector2.ZERO:
		var turn := particle.orbit_velocity * _sample_curve(mat.orbit_velocity_curve, phase) * TAU * delta
		particle.position = emit_origin + offset.rotated(turn)

	# Damping removes a fixed amount of speed per second rather than a ratio.
	if particle.damping > 0.0 and particle.velocity != Vector2.ZERO:
		var speed := particle.velocity.length() \
				- particle.damping * _sample_curve(mat.damping_curve, phase) * delta
		particle.velocity = particle.velocity.normalized() * maxf(speed, 0.0)

	particle.position += particle.velocity * delta

	if sub and mat.sub_emitter_mode == ParticleProcessMaterial.SUB_EMITTER_CONSTANT \
			and mat.sub_emitter_frequency > 0.0:
		var crossings := floori(particle.time * mat.sub_emitter_frequency) \
				- floori(prev_time * mat.sub_emitter_frequency)
		_trigger_sub_emission(sub, mat, particle, crossings)

	# Rotation is not integrated: it is the base angle plus age * velocity * curve,
	# matching the ParticleProcessMaterial shader.
	var angle := particle.base_angle + particle.time * particle.angular_velocity \
			* _sample_curve(mat.angular_velocity_curve, phase)
	particle.rotation = deg_to_rad(angle)
	if mat.particle_flag_align_y and particle.velocity != Vector2.ZERO:
		particle.rotation = atan2(-particle.velocity.x, particle.velocity.y)

	particle.draw_scale = Vector2(particle.base_scale, particle.base_scale) \
			* _sample_scale(mat.scale_curve, phase)
	if absf(particle.draw_scale.x) < _MIN_SCALE:
		particle.draw_scale.x = _MIN_SCALE
	if absf(particle.draw_scale.y) < _MIN_SCALE:
		particle.draw_scale.y = _MIN_SCALE

	# The animation position is in sheet cycles: offset + speed plays through the whole
	# sprite sheet speed+offset times over the particle's lifetime.
	particle.anim_pos = particle.anim_offset * _sample_curve(mat.anim_offset_curve, phase) \
			+ particle.anim_speed * _sample_curve(mat.anim_speed_curve, phase) * phase

	var color := particle.base_color
	var ramp := _gradient_of(mat.color_ramp)
	if ramp:
		color *= ramp.sample(phase)
	if particle.hue_rot != 0.0:
		var hue_angle := TAU * particle.hue_rot * _sample_curve(mat.hue_variation_curve, phase)
		color = _hue_rotated(color, hue_angle)
	color.a *= _sample_curve(mat.alpha_curve, phase)
	particle.draw_color = color


func _draw_particle(particle: _Particle, sim_to_node: Transform2D) -> void:
	var sprite := particle.sprite
	sprite.transform = sim_to_node \
			* Transform2D(particle.rotation, particle.draw_scale, 0.0, particle.position)
	sprite.modulate = particle.draw_color

	if sprite.hframes != _anim_h_frames:
		sprite.hframes = _anim_h_frames
	if sprite.vframes != _anim_v_frames:
		sprite.vframes = _anim_v_frames
	var total_frames := _anim_h_frames * _anim_v_frames
	if total_frames > 1:
		var frame := floori(particle.anim_pos * float(total_frames))
		frame = posmod(frame, total_frames) if _anim_loop else clampi(frame, 0, total_frames - 1)
		if sprite.frame != frame:
			sprite.frame = frame

	sprite.visible = true


func _deactivate(particle: _Particle) -> void:
	particle.active = false
	if is_instance_valid(particle.sprite):
		particle.sprite.visible = false

#endregion


#region Sub-emission

func _resolve_sub_emitter() -> YSortParticles2D:
	if sub_emitter.is_empty():
		return null
	var node := get_node_or_null(sub_emitter)
	if node == self:
		return null
	return node as YSortParticles2D


func _trigger_sub_emission(sub: YSortParticles2D, mat: ParticleProcessMaterial, particle: _Particle, count: int) -> void:
	if count <= 0 or _sub_emission_depth >= _MAX_SUB_EMISSION_DEPTH:
		return

	var global_pos := particle.position
	var global_vel := particle.velocity
	if local_coords:
		global_pos = global_transform * global_pos
		global_vel = global_transform.basis_xform(global_vel)
	var xform := Transform2D(0.0, global_pos)
	var vel := global_vel
	if sub.local_coords and sub.is_inside_tree():
		var to_sub := sub.global_transform.affine_inverse()
		xform = to_sub * xform
		vel = to_sub.basis_xform(vel)

	var flags: int = EmitFlags.EMIT_FLAG_POSITION
	if mat.sub_emitter_keep_velocity:
		flags |= EmitFlags.EMIT_FLAG_VELOCITY

	_sub_emission_depth += 1
	for i in mini(count, sub.amount):
		sub.emit_particle(xform, vel, Color.WHITE, Color.WHITE, flags)
	_sub_emission_depth -= 1

#endregion


#region Helpers

func _material() -> ParticleProcessMaterial:
	if process_material:
		return process_material
	if _fallback_material == null:
		_fallback_material = ParticleProcessMaterial.new()
	return _fallback_material


## Reads sprite-sheet animation settings from a CanvasItemMaterial assigned to this
## node's material slot, the same configuration GPUParticles2D uses.
func _refresh_anim_config() -> void:
	_anim_h_frames = 1
	_anim_v_frames = 1
	_anim_loop = false
	var canvas_material := material as CanvasItemMaterial
	if canvas_material and canvas_material.particles_animation:
		_anim_h_frames = maxi(1, canvas_material.particles_anim_h_frames)
		_anim_v_frames = maxi(1, canvas_material.particles_anim_v_frames)
		_anim_loop = canvas_material.particles_anim_loop


func _cached_image(from_texture: Texture2D) -> Image:
	if from_texture == null:
		return null
	var image: Image = _image_cache.get(from_texture)
	if image == null:
		image = from_texture.get_image()
		if image == null:
			return null
		if image.is_compressed():
			image.decompress()
		_image_cache[from_texture] = image
	return image


static func _image_pixel(image: Image, index: int) -> Color:
	var width := image.get_width()
	@warning_ignore("integer_division")
	return image.get_pixel(index % width, index / width)


static func _sample_curve(curve_texture: Texture2D, phase: float) -> float:
	var typed := curve_texture as CurveTexture
	if typed and typed.curve:
		return typed.curve.sample_baked(phase)
	return 1.0


## Samples a scale curve, supporting both CurveTexture (uniform) and CurveXYZTexture
## (per-axis, using its X and Y curves).
static func _sample_scale(curve_texture: Texture2D, phase: float) -> Vector2:
	var xyz := curve_texture as CurveXYZTexture
	if xyz:
		var x := xyz.curve_x.sample_baked(phase) if xyz.curve_x else 1.0
		var y := xyz.curve_y.sample_baked(phase) if xyz.curve_y else 1.0
		return Vector2(x, y)
	var uniform := _sample_curve(curve_texture, phase)
	return Vector2(uniform, uniform)


static func _gradient_of(ramp: Texture2D) -> Gradient:
	var ramp_1d := ramp as GradientTexture1D
	if ramp_1d:
		return ramp_1d.gradient
	var ramp_2d := ramp as GradientTexture2D
	if ramp_2d:
		return ramp_2d.gradient
	return null


## Rotates the color's hue by [param angle] radians using the same YIQ-based matrix as
## the engine's particle materials. Alpha is unaffected.
static func _hue_rotated(color: Color, angle: float) -> Color:
	if angle == 0.0:
		return color
	var c := cos(angle)
	var s := sin(angle)
	var r := color.r
	var g := color.g
	var b := color.b
	return Color(
		(0.299 + 0.701 * c + 0.168 * s) * r
			+ (0.587 - 0.587 * c + 0.330 * s) * g
			+ (0.114 - 0.114 * c - 0.497 * s) * b,
		(0.299 - 0.299 * c - 0.328 * s) * r
			+ (0.587 + 0.413 * c + 0.035 * s) * g
			+ (0.114 - 0.114 * c + 0.292 * s) * b,
		(0.299 - 0.300 * c + 1.250 * s) * r
			+ (0.587 - 0.588 * c - 1.050 * s) * g
			+ (0.114 + 0.886 * c - 0.203 * s) * b,
		color.a
	)

#endregion
