@tool
class_name SortedParticles2D
extends Node2D
## A particle system that spawns Sprite2D children for Y-sort compatibility.
## Unlike GPUParticles2D, each particle is a separate Sprite2D node that participates in Y-sorting.
## Some ParticleProcessMaterial features are not implemented, including at least:
## - hue_variation
## - hue_variation_curve
## - collision_mode
## - sub_emitter_mode

signal finished


class ParticleData:
	var sprite: Sprite2D
	var age: float = 0.0
	var lifetime: float = 1.0
	var velocity: Vector2 = Vector2.ZERO
	var angular_velocity: float = 0.0
	var base_scale: Vector2 = Vector2.ONE
	var base_color: Color = Color.WHITE
	var damping: float = 0.0
	var spawn_position: Vector2 = Vector2.ZERO  # For local_coords


@export_group("Emission")
@export var emitting: bool = false:
	set(value):
		emitting = value
		if emitting:
			_emission_time = 0.0
			_particles_emitted = 0
			_finished_emitted = false

@export_range(1, 1000000) var amount: int = 8
@export var one_shot: bool = false
@export_range(0.01, 600.0, 0.01, "suffix:s") var lifetime: float = 1.0

@export_group("Time")
@export_range(0.0, 10.0, 0.01) var speed_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var explosiveness: float = 0.0
@export_range(0.0, 1.0, 0.01) var randomness: float = 0.0

@export_group("Drawing")
@export var local_coords: bool = false
@export var texture: Texture2D

@export_group("Process Material")
@export var process_material: ParticleProcessMaterial


var _particles: Array[ParticleData] = []
var _emission_time: float = 0.0
var _particles_emitted: int = 0
var _finished_emitted: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not emitting:
		return
	
	var scaled_delta := delta * speed_scale
	
	if emitting:
		_handle_emission(scaled_delta)
	
	# Update existing particles
	_update_particles(scaled_delta)
	_check_finished()


#region Material Property Accessors

func _get_direction() -> Vector3:
	return process_material.direction if process_material else Vector3(1, 0, 0)

func _get_spread() -> float:
	return process_material.spread if process_material else 45.0

func _get_initial_velocity_min() -> float:
	return process_material.initial_velocity_min if process_material else 0.0

func _get_initial_velocity_max() -> float:
	return process_material.initial_velocity_max if process_material else 0.0

func _get_angular_velocity_min() -> float:
	return process_material.angular_velocity_min if process_material else 0.0

func _get_angular_velocity_max() -> float:
	return process_material.angular_velocity_max if process_material else 0.0

func _get_gravity() -> Vector3:
	return process_material.gravity if process_material else Vector3(0, 980, 0)

func _get_damping_min() -> float:
	return process_material.damping_min if process_material else 0.0

func _get_damping_max() -> float:
	return process_material.damping_max if process_material else 0.0

func _get_scale_min() -> float:
	return process_material.scale_min if process_material else 1.0

func _get_scale_max() -> float:
	return process_material.scale_max if process_material else 1.0

func _get_scale_curve() -> CurveTexture:
	return process_material.scale_curve if process_material else null

func _get_color() -> Color:
	return process_material.color if process_material else Color.WHITE

func _get_color_ramp() -> Texture2D:
	return process_material.color_ramp if process_material else null

func _get_alpha_curve() -> CurveTexture:
	return process_material.alpha_curve if process_material else null

func _get_emission_shape() -> int:
	return process_material.emission_shape if process_material else 0

func _get_emission_sphere_radius() -> float:
	return process_material.emission_sphere_radius if process_material else 1.0

func _get_emission_box_extents() -> Vector3:
	return process_material.emission_box_extents if process_material else Vector3.ONE

#endregion


func _handle_emission(delta: float) -> void:
	if one_shot and _particles_emitted >= amount:
		return
	
	_emission_time += delta
	
	# Calculate the emission period: fraction of lifetime over which particles are emitted
	# explosiveness = 0 → emit over full lifetime
	# explosiveness = 1 → emit all at once (period approaches 0)
	var emission_period := lifetime * (1.0 - explosiveness)
	
	# Emit particles if we haven't emitted all for this cycle
	if _particles_emitted < amount:
		if emission_period <= 0.0:
			while _particles_emitted < amount:
				_spawn_particle()
				_particles_emitted += 1
		else:
			# Spread particles evenly over the emission period
			# Particle i should emit at time: emission_period * i / amount
			var emission_interval := emission_period / float(amount)
			while _particles_emitted < amount:
				var target_time := emission_interval * _particles_emitted
				if _emission_time < target_time:
					break
				_spawn_particle()
				_particles_emitted += 1
	
	# Reset for next cycle when full lifetime has passed
	if not one_shot and _emission_time >= lifetime:
		_emission_time -= lifetime
		_particles_emitted = 0


func _spawn_particle() -> void:
	var particle := ParticleData.new()
	
	var sprite := Sprite2D.new()
	sprite.texture = texture
	add_child(sprite)
	particle.sprite = sprite
	
	particle.lifetime = lifetime * (1.0 - randomness * _rng.randf())
	
	var spawn_offset := _get_emission_position()
	if local_coords:
		sprite.position = spawn_offset
		particle.spawn_position = global_position
	else:
		sprite.global_position = global_position + spawn_offset
	
	particle.velocity = _get_initial_velocity()
	particle.angular_velocity = _rng.randf_range(_get_angular_velocity_min(), _get_angular_velocity_max())
	
	var scale_value := _rng.randf_range(_get_scale_min(), _get_scale_max())
	particle.base_scale = Vector2(scale_value, scale_value)
	sprite.scale = particle.base_scale
	
	particle.base_color = _get_color()
	sprite.modulate = particle.base_color
	
	particle.damping = _rng.randf_range(_get_damping_min(), _get_damping_max())
	
	_particles.append(particle)


func _get_emission_position() -> Vector2:
	var emission_shape := _get_emission_shape()
	var sphere_radius := _get_emission_sphere_radius()
	var box_extents := _get_emission_box_extents()
	
	match emission_shape:
		0:  # EMISSION_SHAPE_POINT
			return Vector2.ZERO
		1:  # EMISSION_SHAPE_SPHERE
			var angle := _rng.randf() * TAU
			var radius := _rng.randf() * sphere_radius
			return Vector2(cos(angle) * radius, sin(angle) * radius)
		2:  # EMISSION_SHAPE_SPHERE_SURFACE
			var angle := _rng.randf() * TAU
			return Vector2(cos(angle) * sphere_radius, sin(angle) * sphere_radius)
		3:  # EMISSION_SHAPE_BOX
			return Vector2(
				_rng.randf_range(-box_extents.x, box_extents.x),
				_rng.randf_range(-box_extents.y, box_extents.y)
			)
		_:
			return Vector2.ZERO


func _get_initial_velocity() -> Vector2:
	var direction := _get_direction()
	var spread := _get_spread()
	var vel_min := _get_initial_velocity_min()
	var vel_max := _get_initial_velocity_max()
	
	var dir_2d := Vector2(direction.x, direction.y).normalized()
	if dir_2d.length_squared() < 0.001:
		dir_2d = Vector2.RIGHT
	
	var spread_rad := deg_to_rad(spread)
	var angle := dir_2d.angle() + _rng.randf_range(-spread_rad, spread_rad)
	var final_direction := Vector2(cos(angle), sin(angle))
	
	return final_direction * _rng.randf_range(vel_min, vel_max)


func _update_particles(delta: float) -> void:
	var gravity := _get_gravity()
	var gravity_2d := Vector2(gravity.x, gravity.y)
	var scale_curve := _get_scale_curve()
	var color_ramp := _get_color_ramp()
	var color_ramp_1d := color_ramp as GradientTexture1D
	var alpha_curve := _get_alpha_curve()
	
	var particles_to_remove: Array[int] = []
	
	for i in range(_particles.size()):
		var particle := _particles[i]
		particle.age += delta
		
		if particle.age >= particle.lifetime:
			particles_to_remove.append(i)
			continue
		
		var life_ratio := particle.age / particle.lifetime
		
		particle.velocity += gravity_2d * delta
		
		if particle.damping > 0.0:
			var damping_factor := maxf(1.0 - particle.damping * delta, 0.0)
			particle.velocity *= damping_factor
		
		if local_coords:
			particle.sprite.position += particle.velocity * delta
		else:
			particle.sprite.global_position += particle.velocity * delta
		
		particle.sprite.rotation += deg_to_rad(particle.angular_velocity) * delta
		
		var scale_multiplier := 1.0
		if scale_curve and scale_curve.curve:
			scale_multiplier = scale_curve.curve.sample(life_ratio)
		particle.sprite.scale = particle.base_scale * scale_multiplier
		
		var final_color: Color
		if color_ramp_1d and color_ramp_1d.gradient:
			final_color = particle.base_color * color_ramp_1d.gradient.sample(life_ratio)
		else:
			final_color = particle.base_color
		
		if alpha_curve and alpha_curve.curve:
			final_color.a *= alpha_curve.curve.sample(life_ratio)
		
		particle.sprite.modulate = final_color
	
	# Remove dead particles (in reverse order to maintain indices)
	for i in range(particles_to_remove.size() - 1, -1, -1):
		var idx := particles_to_remove[i]
		var particle := _particles[idx]
		if is_instance_valid(particle.sprite):
			particle.sprite.queue_free()
		_particles.remove_at(idx)


func _check_finished() -> void:
	if one_shot and _particles_emitted >= amount and _particles.is_empty() and not _finished_emitted:
		_finished_emitted = true
		emitting = false
		finished.emit()


## Restarts the particle emission, clearing all existing particles.
func restart() -> void:
	for particle in _particles:
		if is_instance_valid(particle.sprite):
			particle.sprite.queue_free()
	_particles.clear()
	
	_emission_time = 0.0
	_particles_emitted = 0
	_finished_emitted = false
	emitting = true


## Emits a single particle with manual transform and velocity.
func emit_particle(xform: Transform2D, velocity: Vector2, color: Color, custom: Color, flags: int) -> void:
	var particle := ParticleData.new()
	
	var sprite := Sprite2D.new()
	sprite.texture = texture
	add_child(sprite)
	particle.sprite = sprite
	
	if local_coords:
		sprite.transform = xform
		particle.spawn_position = global_position
	else:
		sprite.global_transform = global_transform * xform
	
	particle.velocity = velocity
	particle.lifetime = lifetime * (1.0 - randomness * _rng.randf())
	particle.angular_velocity = _rng.randf_range(_get_angular_velocity_min(), _get_angular_velocity_max())
	particle.base_scale = xform.get_scale()
	particle.base_color = color
	sprite.modulate = color
	particle.damping = _rng.randf_range(_get_damping_min(), _get_damping_max())
	
	_particles.append(particle)


## Returns a Rect2 containing all currently active particles.
func capture_rect() -> Rect2:
	if _particles.is_empty():
		return Rect2()
	
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	
	for particle in _particles:
		if not is_instance_valid(particle.sprite):
			continue
		
		var pos: Vector2
		if local_coords:
			pos = particle.sprite.position
		else:
			pos = particle.sprite.global_position - global_position
		
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)
	
	if min_pos.x == INF:
		return Rect2()
	
	return Rect2(min_pos, max_pos - min_pos)
